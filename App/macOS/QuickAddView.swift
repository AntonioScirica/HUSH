import SwiftUI
import VaultCore
import LocalAuthentication

/// Il popup della scorciatoia globale (⌘P): l'editor della parete compare
/// SUBITO, sotto il pannello Touch ID di sistema — niente schermate di
/// passaggio che sfarfallano. Finché non sei autenticato l'editor è solo
/// scenografia (disabilitato); Touch ID rifiutato = il popup si chiude.
/// Senza Touch ID attivo si passa dalla master password, sopra l'editor.
struct QuickAddView: View {
    let onDone: () -> Void

    @State private var progettoScelto: VaultFileManager.Project?
    @State private var autenticato = false
    @State private var chiediPassword = false
    /// L'editor la usa solo per il ramo "elimina voce", che qui (voce
    /// sempre nuova) non si può raggiungere — ma l'environment va riempito.
    @StateObject private var vm = VaultViewModel()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // il cassetto si sceglie qui, in testa: sotto c'è
                // direttamente l'editor con le categorie, senza passi
                // intermedi. Stessa tendina fatta in casa della parete:
                // il Menu di sistema stonerebbe con la carta del resto.
                if VaultFileManager.shared.projects.count > 1 {
                    TendinaCassetto(scelto: $progettoScelto)
                        .padding(.horizontal, 26)
                        .padding(.top, 18)
                        .padding(.bottom, 4)
                        // Senza questo la tendina aperta finisce SOTTO
                        // l'editor: l'overlay vive dentro TendinaCassetto,
                        // ma il fratello successivo della VStack si disegna
                        // dopo di lei e la copre — lo zIndex va alzato qui,
                        // al livello dei fratelli, non dentro la tendina.
                        .zIndex(1)
                }

                EntryEditorView(
                    entry: nil,
                    onSave: { voce in
                        guard autenticato else { return }
                        if let progettoScelto {
                            VaultLibrary.shared.add(voce, to: progettoScelto)
                        }
                        onDone()
                    },
                    onCancel: { onDone() }
                )
                .environmentObject(vm)
            }
            .disabled(!autenticato)

            if chiediPassword {
                PasswordRapida(
                    onSbloccato: { autenticato = true; chiediPassword = false },
                    onAnnulla: { onDone() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .preferredColorScheme(.light) // il pannello non deve seguire il tema scuro: testi neri su carta
        .onExitCommand { onDone() } // Esc chiude
        .task {
            progettoScelto = VaultFileManager.shared.projects.first
            // Se il caveau è già sbloccato (l'app è aperta e attiva) non ha
            // senso chiedere di nuovo il dito: Touch ID/password servono
            // solo a sbloccarlo, non a riconfermare un accesso già in corso.
            guard !MasterKey.isUnlocked else {
                autenticato = true
                return
            }
            // Da bloccato invece SEMPRE: il popup si richiama da qualunque
            // app, e chiunque passi davanti al Mac non deve poter scrivere
            // nel caveau senza autenticarsi.
            guard MasterKey.biometryUsable else {
                chiediPassword = true
                return
            }
            MasterKey.unlockWithBiometry { ok in
                DispatchQueue.main.async {
                    if ok { autenticato = true } else { onDone() } // rifiutato: si chiude
                }
            }
        }
    }
}

// MARK: - Master password (solo senza Touch ID)

private struct PasswordRapida: View {
    let onSbloccato: () -> Void
    let onAnnulla: () -> Void

    @State private var password = ""
    @State private var errore: String?

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            SecureField("Master password", text: $password)
                .textFieldStyle(PaperFieldStyle())
                .onSubmit(prova)

            if let errore {
                Text(errore).font(Theme.mono(10)).foregroundStyle(Theme.danger)
            }

            Button("Sblocca") { prova() }
                .buttonStyle(InkButtonStyle(prominent: true))
                .disabled(password.isEmpty)
                .opacity(password.isEmpty ? 0.4 : 1)
            Spacer()
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }

    private func prova() {
        if MasterKey.unlock(password: password) {
            onSbloccato()
        } else {
            errore = "Password sbagliata."
            password = ""
        }
    }
}

// MARK: - Tendina cassetto (stesso stile della parete)

private struct TendinaCassetto: View {
    @Binding var scelto: VaultFileManager.Project?
    @State private var aperta = false
    @State private var creando = false
    @State private var nomeNuovo = ""
    @State private var creazioneInCorso = false
    @State private var creazioneErrore: String?
    private static let altezzaCampo: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CASSETTO")
                .font(Theme.mono(9, .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.inkSoft)

            Button {
                withAnimation(.easeOut(duration: 0.15)) { aperta.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(scelto?.name ?? "cassetto")
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .rotationEffect(.degrees(aperta ? 180 : 0))
                }
                .padding(.horizontal, 10)
                .frame(height: Self.altezzaCampo)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.paperRaised)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // La tendina è agganciata al BOTTONE, fuori dal flusso (non
            // spinge giù l'editor): overlay allineato in alto e spostato di
            // un'altezza-campo, così il suo bordo superiore parte 4 punti
            // sotto il bordo inferiore del campo — un dropdown normale.
            // Campo ad altezza FISSA apposta: l'offset è un numero certo,
            // niente GeometryReader né alignmentGuide (provati entrambi:
            // il primo misurava dalla cima sbagliata, la seconda ancorava
            // la lista sopra il campo invece che sotto).
            .overlay(alignment: .topLeading) {
                if aperta {
                    listaProgetti.offset(y: Self.altezzaCampo + 4)
                }
            }
        }
    }

    private var listaProgetti: some View {
        let progetti = VaultFileManager.shared.projects
        // Righe ad altezza fissa così l'altezza totale è calcolabile: la
        // tendina vive in un overlay, che le propone la misura del BOTTONE —
        // un maxHeight qui collasserebbe la ScrollView a quell'altezza
        // (succedeva: si vedeva una riga sola, "tagliata"). L'altezza va
        // quindi imposta noi: tutta la lista se è corta, tetto a 4 righe e
        // mezza (si capisce che sotto c'è altro da scorrere) se è lunga —
        // +1 riga sempre, per "nuovo cassetto" in fondo.
        let altezzaRiga: CGFloat = 40
        let altezzaLista = min(CGFloat(progetti.count + 1) * (altezzaRiga + 1) - 1, altezzaRiga * 4.5)
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(progetti.enumerated()), id: \.element.id) { i, p in
                    Button {
                        scelto = p
                        withAnimation(.easeOut(duration: 0.15)) { aperta = false }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: p.icon ?? "folder")
                                .font(.system(size: 12))
                                .frame(width: 16)
                            Text(p.name)
                                .font(Theme.mono(12, .semibold))
                            Spacer(minLength: 0)
                            if p.id == scelto?.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .frame(height: altezzaRiga)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
                rigaNuovoCassetto(altezza: altezzaRiga)
            }
        }
        .frame(height: altezzaLista)
        .background(Theme.paperRaised)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }

    /// Ultima riga della tendina: "+ nuovo cassetto", che si trasforma in un
    /// campo di testo sul posto. Un cassetto è un .kdbx a sé cifrato con la
    /// stessa master password di sessione — niente password extra da
    /// chiedere, si è già dentro.
    private func rigaNuovoCassetto(altezza: CGFloat) -> some View {
        Group {
            if creando {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .frame(width: 16)
                        .foregroundStyle(Theme.inkSoft)
                    TextField("nome cassetto", text: $nomeNuovo)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(12, .semibold))
                        .disabled(creazioneInCorso)
                        .onSubmit { creaCassetto() }
                    if creazioneInCorso {
                        ProgressView().controlSize(.small)
                    } else {
                        Button { creaCassetto() } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .disabled(nomeNuovo.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .frame(height: altezza)
            } else {
                Button {
                    creando = true
                    creazioneErrore = nil
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text("nuovo cassetto")
                            .font(Theme.mono(12, .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: altezza)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let creazioneErrore {
                Text(creazioneErrore)
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
        }
    }

    private func creaCassetto() {
        let nome = nomeNuovo.trimmingCharacters(in: .whitespaces)
        guard !nome.isEmpty, let key = MasterKey.session else { return }
        creazioneInCorso = true
        let nuovaVM = VaultViewModel()
        nuovaVM.createNew(name: nome, password: key)
        Task { @MainActor in
            guard let bytes = await nuovaVM.save() else {
                creazioneInCorso = false
                creazioneErrore = "Creazione non riuscita."
                return
            }
            do {
                let url = VaultFileManager.shared.freeProjectURL(named: nome)
                try Data(bytes).write(to: url, options: .atomic)
                try VaultFileManager.shared.addProject(name: nome, url: url)
                if let creato = VaultFileManager.shared.projects.first(where: { $0.path == url.path }) {
                    scelto = creato
                }
                creando = false
                nomeNuovo = ""
                withAnimation(.easeOut(duration: 0.15)) { aperta = false }
            } catch {
                creazioneErrore = "Salvataggio non riuscito."
            }
            creazioneInCorso = false
        }
    }
}


