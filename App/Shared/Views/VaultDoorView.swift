import SwiftUI

/// Porta del caveau in line-art: gli stessi tratti neri su carta della parete
/// di cassetti, ma in 2D. È la schermata di sblocco — una password sola apre
/// tutto lo scrigno, quindi qui c'è una porta sola.
struct VaultDoorView: View {
    let onUnlocked: () -> Void

    @State private var password = ""
    @State private var wrong = false
    @State private var checking = false
    /// Gradi del volantino: gira mentre scrivi e fa il giro completo all'apertura.
    @State private var wheelAngle: Double = 0
    @State private var opening = false
    @State private var rememberWithBiometry = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()

            VStack(spacing: 34) {
                VaultDoorShape(wheelAngle: wheelAngle)
                    .frame(width: 260, height: 260)
                    // all'apertura la porta avanza verso di te e sfuma
                    .scaleEffect(opening ? 2.6 : 1)
                    .opacity(opening ? 0 : 1)
                    .offset(x: wrong ? 0 : 0)

                if !opening {
                    VStack(spacing: 18) {
                        VStack(spacing: 6) {
                            Text("SCRIGNO")
                                .font(Theme.display(38))
                                .kerning(-0.5)
                                .foregroundStyle(Theme.ink)
                            Text("una password, tutti i cassetti")
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.inkSoft)
                        }

                        VStack(spacing: 10) {
                            SecureField("master password", text: $password)
                                .textFieldStyle(PaperFieldStyle())
                                .focused($fieldFocused)
                                .onSubmit(attempt)
                                .frame(width: 280)
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(Theme.danger, lineWidth: wrong ? 1.4 : 0)
                                )

                            if wrong {
                                Text("password sbagliata")
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.danger)
                            }

                            Button(checking ? "apro…" : "apri") { attempt() }
                                .buttonStyle(InkButtonStyle(prominent: true))
                                .frame(width: 280)
                                .disabled(password.isEmpty || checking)
                                .opacity(password.isEmpty || checking ? 0.4 : 1)

                            if MasterKey.biometryUsable {
                                Button {
                                    MasterKey.unlockWithBiometry { ok in
                                        if ok { open() }
                                        // annullare il prompt non è un errore:
                                        // niente scrollata, resta lì com'era
                                    }
                                } label: {
                                    Label("sblocca col dito", systemImage: "touchid")
                                }
                                .buttonStyle(OutlineButtonStyle())
                                .frame(width: 280)
                            } else if MasterKey.biometryEnabled {
                                Text("oggi la password va scritta a mano,\nper non dimenticarla")
                                    .font(Theme.mono(10))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(Theme.inkSoft)
                                    .frame(width: 280)
                            } else if MasterKey.biometryAvailable {
                                // via di riattivazione: se l'onboarding è stato
                                // saltato (o non era andato a buon fine) il dito
                                // si accende da qui, alla prossima apertura
                                Toggle(isOn: $rememberWithBiometry) {
                                    Text("ricordami col dito")
                                        .font(Theme.mono(11))
                                        .foregroundStyle(Theme.inkSoft)
                                }
                                .toggleStyle(.checkbox)
                                .frame(width: 280, alignment: .leading)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            // il campo trema quando sbagli, come una maniglia che non cede
            .offset(x: wrong ? -6 : 0)
        }
        .preferredColorScheme(.light)
        .onAppear { fieldFocused = true }
        // il volantino si muove mentre digiti: la porta "risponde"
        .onChange(of: password) { _, value in
            withAnimation(.easeOut(duration: 0.25)) {
                wheelAngle = Double(value.count) * 9
                wrong = false
            }
        }
    }

    private func attempt() {
        guard !password.isEmpty, !checking else { return }
        checking = true
        // il verificatore è volutamente lento: fuori dal thread principale,
        // se no la finestra si pianta per un attimo a ogni tentativo
        let typed = password
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = MasterKey.unlock(password: typed)
            DispatchQueue.main.async {
                checking = false
                guard ok else { fail(); return }
                if rememberWithBiometry { try? MasterKey.enableBiometry(password: typed) }
                open()
            }
        }
    }

    private func open() {
        withAnimation(.easeInOut(duration: 0.9)) {
            wheelAngle += 720
            opening = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { onUnlocked() }
    }

    private func fail() {
        password = ""
        withAnimation(.default) { wrong = true }
        // scrollata secca: due rimbalzi e torna dritta
        withAnimation(.easeInOut(duration: 0.08).repeatCount(4, autoreverses: true)) {
            wheelAngle -= 6
        }
        fieldFocused = true
    }
}

/// Il disegno vero e proprio: cerchi concentrici, chiavistelli tutt'attorno
/// e volantino a tre razze. Solo contorni, nessuna ombra — come i cassetti.
private struct VaultDoorShape: View {
    let wheelAngle: Double

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // battuta esterna e anta
                Circle().strokeBorder(Theme.line, lineWidth: 1.2)
                    .frame(width: s, height: s)
                Circle().fill(Theme.paperRaised)
                    .frame(width: s * 0.9, height: s * 0.9)
                Circle().strokeBorder(Theme.line, lineWidth: 1.2)
                    .frame(width: s * 0.9, height: s * 0.9)

                // chiavistelli sul bordo
                ForEach(0..<8, id: \.self) { i in
                    Rectangle()
                        .fill(Theme.paper)
                        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                        .frame(width: s * 0.055, height: s * 0.085)
                        .offset(y: -s * 0.45)
                        .rotationEffect(.degrees(Double(i) * 45))
                }

                // anelli interni
                Circle().strokeBorder(Theme.line.opacity(0.7), lineWidth: 1)
                    .frame(width: s * 0.68, height: s * 0.68)
                Circle().strokeBorder(Theme.line.opacity(0.7), lineWidth: 1)
                    .frame(width: s * 0.54, height: s * 0.54)

                wheel(s: s)
                    .rotationEffect(.degrees(wheelAngle))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func wheel(s: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(Theme.paper)
                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                    .frame(width: s * 0.4, height: s * 0.055)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
            // cerchione: solo contorno, se no coprirebbe le razze
            Circle().strokeBorder(Theme.line, lineWidth: 1.2)
                .frame(width: s * 0.42, height: s * 0.42)
            Circle().fill(Theme.paper)
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1.2))
                .frame(width: s * 0.13, height: s * 0.13)
        }
    }
}
