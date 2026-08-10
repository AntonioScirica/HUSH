import SwiftUI

/// Porta del caveau in line-art: gli stessi tratti neri su carta della parete
/// di cassetti, ma in 2D. È la schermata di sblocco — una password sola apre
/// tutto Hush, quindi qui c'è una porta sola.
struct VaultDoorView: View {
    /// Vero quando si arriva qui richiudendo Hush, non all'avvio: in
    /// quel caso la porta rifà l'apertura al contrario invece di comparire
    /// già chiusa.
    var closing = false
    /// Scatta appena la password è giusta e l'anta comincia a muoversi:
    /// chi sta dietro ha ~1,6s per farsi trovare già pronto nel vano.
    var onOpeningStarted: () -> Void = {}
    let onUnlocked: () -> Void

    @State private var password = ""
    @State private var wrong = false
    @State private var checking = false
    /// Gradi del volantino: gira mentre scrivi e fa il giro completo all'apertura.
    @State private var wheelAngle: Double = 0
    @State private var opening = false
    /// Gradi di apertura dell'anta attorno al perno sinistro.
    @State private var doorSwing: Double = 0
    /// Muro e anta insieme: crescono finché il vano non ha inghiottito lo
    /// schermo. È la sensazione di attraversare la porta, non di guardarla.
    @State private var frontScale: CGFloat = 1
    /// Dopo una chiusura volontaria non si richiede il dito da soli: sarebbe
    /// un riaprire subito quel che si è appena chiuso. Si aspetta un tocco.
    @State private var waitingTap = false
    /// Col dito configurato la porta si apre da sé: la password compare solo
    /// se il dito non va (o se è il giorno in cui va comunque riscritta).
    @State private var askPassword = false
    /// Recupero con la chiave di scorta.
    @State private var showRecovery = false
    @State private var recoveryKey = ""
    @State private var recoveryError: String?
    @FocusState private var fieldFocused: Bool

    /// Diametro dell'anta: grande quando basta il dito, più piccola quando
    /// sotto ci vanno campo e bottone.
    private var doorSize: CGFloat { askPassword ? 240 : 380 }
    /// Quanto sta sopra al centro, per far stare i controlli sotto. In
    /// apertura torna al centro: si attraversa il vano, e il vano deve stare
    /// davanti alla camera.
    private var doorCenterY: CGFloat {
        if opening { return 0 }
        return askPassword ? -80 : 0
    }

    var body: some View {
        // Un unico ZStack che ignora il safe area TUTTO INSIEME: prima il
        // muro lo ignorava da solo e il suo centro non coincideva con quello
        // del disco, per questo la porta risultava fuori asse rispetto al foro.
        // Sfondo trasparente: dietro c'è la home vera, quella stessa che
        // resterà a fine animazione. Prima qui ci stava una copia della
        // parete e allo sblocco le due viste si scambiavano — bastava un
        // pelo di differenza fra le due camere per vedere uno scatto.
        // Ora non c'è nessuno scambio: si toglie di mezzo solo la porta.
        ZStack {
            // Muro e anta viaggiano insieme: entrambi crescono mentre si
            // entra, così il vano si allarga fino a superare i bordi dello
            // schermo e ci si passa attraverso.
            ZStack {
                // Il muro è fermo: si apre solo la porta, quindi il muro ha un
                // foro tondo esattamente dove sta l'anta ed è da lì che si
                // intravede la parete dietro.
                WallWithHole(diameter: doorSize, centerY: doorCenterY)
                    .fill(Theme.paper, style: FillStyle(eoFill: true))

                // battuta del vano: il bordo del foro
                Circle()
                    .strokeBorder(Theme.line, lineWidth: 1.2)
                    .frame(width: doorSize, height: doorSize)
                    .offset(y: doorCenterY)

                // L'anta vera e propria: solo questa ruota, sul perno sinistro.
                ZStack {
                    Circle().fill(Theme.paper)
                    VaultDoorShape(wheelAngle: wheelAngle)
                }
                .frame(width: doorSize, height: doorSize)
                .offset(y: doorCenterY)
                // perno a sinistra: l'anta ruota attorno al proprio bordo e si
                // apre verso di te, scoprendo il vano
                .rotation3DEffect(
                    .degrees(doorSwing),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .leading,
                    perspective: 0.55
                )
                // trema quando sbagli, come una maniglia che non cede
                .offset(x: wrong ? -6 : 0)
                // dopo una chiusura volontaria si riapre toccandola
                .onTapGesture {
                    guard waitingTap else { return }
                    waitingTap = false
                    start()
                }
            }
            .scaleEffect(frontScale)

            // Controlli sotto l'anta, sul muro fermo
            if !opening {
                Group {
                    if askPassword {
                        passwordControls
                    } else {
                        Text(waitingTap ? "tocca la porta per aprire"
                                        : (MasterKey.tipoBiometria == .volto ? "guarda lo schermo" : "appoggia il dito sul sensore"))
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .offset(y: doorCenterY + doorSize / 2 + (askPassword ? 130 : 34))
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.35), value: askPassword)
        .sheet(isPresented: $showRecovery) {
            recoverySheet
        }
        .onAppear {
            if closing {
                // arriva già "aperta": la richiude sotto gli occhi
                opening = true
                playClosing()
            } else {
                start()
            }
        }
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
                Text("HUSH")
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

                if RecoveryKit.exists {
                    Button("password dimenticata?") { showRecovery = true }
                        .buttonStyle(.plain)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    // MARK: - Avvio

    /// Chiusura volontaria: si rifà l'apertura al rovescio, dal vano
    /// spalancato fino all'anta accostata e al volantino che torna indietro.
    private func playClosing() {
        doorSwing = -105
        frontScale = 4.6

        withAnimation(.easeOut(duration: 0.7)) { frontScale = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeInOut(duration: 0.9)) { doorSwing = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeInOut(duration: 0.5)) { wheelAngle = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            opening = false
            if MasterKey.biometryUsable {
                waitingTap = true
            } else {
                askPassword = true
                fieldFocused = true
            }
        }
    }

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

    /// Rientro con la chiave di scorta: restituisce la master password vera,
    /// quindi non c'è niente da ricifrare — si entra e basta.
    private var recoverySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            IndexLabel(text: "chiave di recupero")
            Rectangle().fill(Theme.line).frame(height: 1.2)

            Text("quella generata al primo avvio. si può scrivere\nanche senza trattini.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            TextField("XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX", text: $recoveryKey)
                .textFieldStyle(PaperFieldStyle())
                .onSubmit(attemptRecovery)

            if let recoveryError {
                Text(recoveryError).font(Theme.mono(11)).foregroundStyle(Theme.danger)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button("annulla") { showRecovery = false; recoveryKey = ""; recoveryError = nil }
                    .buttonStyle(OutlineButtonStyle())
                Button("rientra") { attemptRecovery() }
                    .buttonStyle(InkButtonStyle(prominent: true))
                    .disabled(recoveryKey.isEmpty)
                    .opacity(recoveryKey.isEmpty ? 0.4 : 1)
            }
        }
        .padding(30)
        .frame(width: 420, height: 320)
        .background(Theme.paper)
        .preferredColorScheme(.light)
    }

    private func attemptRecovery() {
        do {
            let master = try RecoveryKit.recover(with: recoveryKey)
            guard MasterKey.unlock(password: master) else {
                recoveryError = "La chiave è valida ma la password recuperata non apre più Hush."
                return
            }
            recoveryKey = ""
            showRecovery = false
            open()
        } catch {
            recoveryError = error.localizedDescription
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
                open()
            }
        }
    }

    /// Sequenza: il volantino gira e sblocca i chiavistelli, poi l'anta si
    /// stacca e ruota sul perno scoprendo la parete. Solo a fine corsa si
    /// passa alla schermata vera.
    private func open() {
        onOpeningStarted()
        withAnimation(.easeInOut(duration: 0.45)) {
            wheelAngle += 720
            opening = true
        }
        // l'anta parte quando il volantino ha finito di girare
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.9)) {
                doorSwing = -105
            }
        }
        // la spinta in avanti entra ad anta ormai quasi aperta: muro e porta
        // crescono fin oltre lo schermo e ci si passa in mezzo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.easeIn(duration: 0.7)) {
                frontScale = 4.6
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { onUnlocked() }
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

/// Il muro del caveau: pieno, con un foro tondo dove sta l'anta. Riempito a
/// even-odd, così il cerchio diventa un buco vero e lascia vedere la parete
/// di cassetti che sta dietro.
private struct WallWithHole: Shape {
    var diameter: CGFloat
    var centerY: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(diameter, centerY) }
        set { diameter = newValue.first; centerY = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        p.addEllipse(in: CGRect(x: rect.midX - diameter / 2,
                                y: rect.midY - diameter / 2 + centerY,
                                width: diameter,
                                height: diameter))
        return p
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
