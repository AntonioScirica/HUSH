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
    /// Gradi di apertura dell'anta attorno al perno sinistro.
    @State private var doorSwing: Double = 0
    @State private var rememberWithBiometry = false
    /// Col dito configurato la porta si apre da sé: la password compare solo
    /// se il dito non va (o se è il giorno in cui va comunque riscritta).
    @State private var askPassword = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            // Dietro c'è già la parete dei cassetti: quando l'anta gira la
            // vedi comparire, prima ancora di entrarci dentro. Nessuna
            // etichetta, però — i nomi dei progetti non si leggono da fuori.
            LockedWallBackdrop()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // L'anta: tutto il fronte è un pezzo solo, incernierato a
            // sinistra come una vera porta blindata.
            ZStack {
                Theme.paper.ignoresSafeArea()

                VStack(spacing: 34) {
                    VaultDoorShape(wheelAngle: wheelAngle)
                        // grande e sola quando basta il dito, più piccola
                        // quando sotto ci va il campo della password
                        .frame(width: askPassword ? 240 : 380,
                               height: askPassword ? 240 : 380)

                    if !opening {
                        if askPassword {
                            passwordControls
                                .transition(.opacity)
                        } else {
                            Text("appoggia il dito sul sensore")
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.inkSoft)
                                .transition(.opacity)
                        }
                    }
                }
                // il campo trema quando sbagli, come una maniglia che non cede
                .offset(x: wrong ? -6 : 0)

                // cardini sul lato del perno
                VStack(spacing: 90) {
                    ForEach(0..<2, id: \.self) { _ in
                        Rectangle()
                            .fill(Theme.paperRaised)
                            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                            .frame(width: 26, height: 54)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
            }
            // perno a sinistra: l'anta ruota attorno al proprio bordo e si
            // apre verso di te, scoprendo la parete
            .rotation3DEffect(
                .degrees(doorSwing),
                axis: (x: 0, y: 1, z: 0),
                anchor: .leading,
                perspective: 0.45
            )
        }
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.35), value: askPassword)
        .onAppear(perform: start)
        // il volantino si muove mentre digiti: la porta "risponde"
        .onChange(of: password) { _, value in
            withAnimation(.easeOut(duration: 0.25)) {
                wheelAngle = Double(value.count) * 9
                wrong = false
            }
        }
    }

    // MARK: - Controlli password (solo quando servono)

    @ViewBuilder private var passwordControls: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("SCRIGNO")
                    .font(Theme.display(32))
                    .kerning(-0.5)
                    .foregroundStyle(Theme.ink)
                Text(MasterKey.biometryEnabled && MasterKey.mustTypePassword
                     ? "oggi la password va scritta a mano, per non dimenticarla"
                     : "una password, tutti i cassetti")
                    .font(Theme.mono(11))
                    .multilineTextAlignment(.center)
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

                // via di accensione del dito quando non è ancora attivo
                if MasterKey.biometryAvailable && !MasterKey.biometryEnabled {
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
    }

    // MARK: - Avvio

    /// Col dito pronto la porta ci prova da sola, senza far cliccare niente.
    /// Se il dito non va — o se è scaduto il giro in cui la password va
    /// comunque riscritta — si passa al campo, e da lì non si torna indietro.
    private func start() {
        guard MasterKey.biometryUsable else {
            askPassword = true
            fieldFocused = true
            return
        }
        MasterKey.unlockWithBiometry { ok in
            if ok {
                open()
            } else {
                askPassword = true
                fieldFocused = true
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

    /// Sequenza: il volantino gira e sblocca i chiavistelli, poi l'anta si
    /// stacca e ruota sul perno scoprendo la parete. Solo a fine corsa si
    /// passa alla schermata vera.
    private func open() {
        withAnimation(.easeInOut(duration: 0.75)) {
            wheelAngle += 720
            opening = true
        }
        // l'anta parte quando il volantino ha finito di girare
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 1.15)) {
                doorSwing = -105
            }
        }
        // ...e la parete resta scoperta un istante prima del cambio schermata
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.85) { onUnlocked() }
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

/// La parete di cassetti come si vede da dietro l'anta: la stessa scena 3D
/// della home, ma muta. Niente targhette, niente post-it, niente voci: a
/// scrigno chiuso non si deve leggere nemmeno come si chiamano i progetti.
private struct LockedWallBackdrop: View {
    private let cols = 13
    private let rows = 9

    var body: some View {
        DrawerWall3D(
            cols: cols,
            rows: rows,
            visibleCols: 5,
            visibleRows: 5,
            centerIndex: (rows / 2) * cols + cols / 2,
            labels: Array(repeating: nil, count: cols * rows),
            icons: Array(repeating: nil, count: cols * rows),
            noteColors: Array(repeating: nil, count: cols * rows),
            entriesByCell: Array(repeating: [], count: cols * rows),
            openCell: .constant(nil),
            selectedFolder: .constant(nil),
            revealFolder: .constant(nil),
            folderBodyHeight: DrawerWall3D.folderExtractedMinH,
            folderRect: .constant(nil),
            creatingCell: .constant(nil),
            plateRect: .constant(nil),
            focusNote: .constant(false),
            noteRect: .constant(nil),
            draftLabel: "",
            draftIcon: nil,
            draftNoteColor: nil,
            onTapNewEntry: {}
        )
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
