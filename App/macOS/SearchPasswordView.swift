import SwiftUI
import VaultCore
import LocalAuthentication
import AppKit

/// Il popup della scorciatoia globale ⌃⌘P: stessa meccanica di
/// `QuickAddView` (Touch ID sempre, anche a sessione già aperta), ma invece
/// di creare una voce nuova la cerca e ne copia la password. Solo la barra
/// finché non si scrive — il cartoncino dei risultati compare sotto (e il
/// pannello si allarga) solo quando c'è qualcosa da mostrare, come
/// Spotlight: mai un riquadro vuoto pieno a occupare lo schermo.
struct SearchPasswordView: View {
    let onDone: () -> Void
    /// Avvisa che l'autenticazione è finita: solo da qui in poi un click
    /// fuori dal pannello deve chiuderlo. Il pannello di sistema di Touch ID
    /// ruba il fuoco anche lui — se il "chiudi al click fuori" fosse già
    /// attivo lo scambierebbe per un click fuori e chiuderebbe tutto a metà.
    let onAutenticato: () -> Void

    @State private var autenticato = false
    @State private var chiediPassword = false
    @State private var query = ""
    /// Voce scelta dai risultati: non copia più subito la password, mostra
    /// prima quali dei suoi campi si possono copiare — un contatto o una
    /// carta hanno più di una cosa utile, non solo una password.
    @State private var selezionato: Match?
    @ObservedObject private var libreria = VaultLibrary.shared
    @FocusState private var cercaAttivo: Bool

    private static let altezzaBarra: CGFloat = 54
    private static let altezzaRiga: CGFloat = 56
    /// Righe visibili prima di dover scorrere: il pannello resta a misura
    /// fissa (vedi SearchPanel), ma i risultati oltre questa soglia non
    /// sparivano semplicemente — non c'era proprio ScrollView, quindi non si
    /// poteva scorrere per vederli.
    private static let righeVisibili = 5
    /// Quante voci tenere in memoria come risultato: più delle righe
    /// visibili, apposta, o non ci sarebbe nulla da scorrere.
    private static let massimoRisultati = 20

    private struct Match: Identifiable {
        let entry: VaultEntry
        let project: VaultFileManager.Project
        var id: UUID { entry.id }
    }

    private var risultati: [Match] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let tutti = VaultFileManager.shared.projects
            .filter { libreria.isLoaded($0) }
            .flatMap { project in libreria.entries(of: project).map { Match(entry: $0, project: project) } }
        // Cerca in QUALSIASI campo della voce, non solo titolo e utente:
        // url, note e campi personalizzati sono spesso l'unico indizio che
        // ci si ricorda ("quella voce con dentro il numero di telefono...").
        // La password resta fuori apposta: cercarla per contenuto vorrebbe
        // dire scriverla in chiaro nel campo di ricerca.
        return tutti
            .filter { match in
                let entry = match.entry
                if entry.title.lowercased().contains(q)
                    || entry.username.lowercased().contains(q)
                    || entry.url.lowercased().contains(q)
                    || entry.notes.lowercased().contains(q)
                    || match.project.name.lowercased().contains(q) { return true }
                return entry.customFields.contains { $0.key.lowercased().contains(q) || $0.value.lowercased().contains(q) }
            }
            .sorted { $0.entry.title.lowercased() < $1.entry.title.lowercased() }
            .prefix(Self.massimoRisultati)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 10) {
            if chiediPassword {
                PasswordRapidaRicerca(
                    onSbloccato: { autenticato = true; chiediPassword = false; avviaCaricamento() },
                    onAnnulla: onDone
                )
            } else if let selezionato {
                barraSelezionato(selezionato)
                dettaglioCampi(selezionato)
            } else {
                barra
                if !risultati.isEmpty { cartoncinoRisultati }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .top)
        .preferredColorScheme(.light) // testo scuro su carta chiara, mai il contrario col tema di sistema
        .onExitCommand {
            // Esc torna prima alla lista, se si era entrati nel dettaglio
            // di una voce: solo se si è già alla ricerca chiude il popup.
            if selezionato != nil { selezionato = nil } else { onDone() }
        }
        .task {
            // Se il caveau è già sbloccato non richiedere di nuovo il dito:
            // vedi lo stesso ragionamento in QuickAddView.
            guard !MasterKey.isUnlocked else {
                autenticato = true
                avviaCaricamento()
                onAutenticato()
                return
            }
            // Da bloccato invece SEMPRE: il popup si richiama da qualunque
            // app, e chiunque passi davanti al Mac non deve poter leggere
            // il caveau senza autenticarsi.
            guard MasterKey.biometryUsable else {
                autenticato = true
                chiediPassword = true
                onAutenticato() // niente pannello di sistema qui: nessun rischio di fuoco rubato
                return
            }
            MasterKey.unlockWithBiometry { ok in
                DispatchQueue.main.async {
                    if ok {
                        autenticato = true
                        avviaCaricamento()
                        onAutenticato() // solo ORA: prima il pannello Touch ID aveva già il fuoco
                    } else {
                        onDone() // rifiutato: si chiude
                    }
                }
            }
        }
        .onChange(of: autenticato) { _, ok in
            // Non nella stessa transazione dello sblocco: il campo è ancora
            // disabled() in quell'istante, e SwiftUI non sposta il fuoco su
            // un campo che sta per diventare abilitato, solo su uno che lo
            // è già.
            if ok { cercaAttivo = true }
        }
    }

    private var barra: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkSoft)
            TextField("Cerca una voce…", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.mono(16))
                .foregroundStyle(Theme.ink)
                .focused($cercaAttivo)
                .onSubmit { copia(risultati.first) }
                .disabled(!autenticato)
        }
        .padding(.horizontal, 18)
        .frame(height: Self.altezzaBarra)
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1.2))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    private var cartoncinoRisultati: some View {
        ScrollView {
            VStack(spacing: 0) {
            ForEach(risultati) { match in
                // Click SCEGLIE la voce, non copia più subito la password:
                // una voce può avere utente, url, note oltre alla password,
                // e prima non c'era modo di prendere altro che lei.
                Button { selezionato = match } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.entry.title.isEmpty ? "senza titolo" : match.entry.title)
                                .font(Theme.mono(13, .semibold))
                                .foregroundStyle(Theme.ink)
                            Text([match.entry.username, match.project.name].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: Self.altezzaRiga)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if match.id != risultati.last?.id {
                    Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 1)
                }
            }
            }
        }
        .frame(height: min(CGFloat(risultati.count), CGFloat(Self.righeVisibili)) * Self.altezzaRiga)
        .background(Theme.paper)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1.2))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    /// Barra sopra il dettaglio: freccia indietro alla lista + titolo della
    /// voce scelta, al posto del campo di ricerca.
    private func barraSelezionato(_ match: Match) -> some View {
        HStack(spacing: 10) {
            Button { selezionato = nil } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
            Text(match.entry.title.isEmpty ? "senza titolo" : match.entry.title)
                .font(Theme.mono(16, .semibold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: Self.altezzaBarra)
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1.2))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    /// I campi copiabili della voce scelta: solo quelli valorizzati, nello
    /// stesso ordine in cui compaiono nell'editor.
    private func campiCopiabili(_ entry: VaultEntry) -> [(icona: String, nome: String, valore: String)] {
        var campi: [(String, String, String)] = []
        if !entry.username.isEmpty { campi.append(("person", "Utente", entry.username)) }
        if !entry.password.isEmpty { campi.append(("key", "Password", entry.password)) }
        if !entry.url.isEmpty { campi.append(("link", "Url", entry.url)) }
        if !entry.notes.isEmpty { campi.append(("note.text", "Note", entry.notes)) }
        for campo in entry.customFields where !campo.value.isEmpty && campo.key != EntryMapping.kindKey {
            campi.append(("textformat", campo.key, campo.value))
        }
        return campi
    }

    private func dettaglioCampi(_ match: Match) -> some View {
        let campi = campiCopiabili(match.entry)
        return Group {
            if campi.isEmpty {
                Text("nessun campo da copiare")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Theme.paper)
            } else {
                // Righe ad altezza fissa dentro una ScrollView: una voce con
                // molti campi extra (contatto, carta) non deve sforare il
                // pannello a misura fissa — stesso motivo per cui la
                // tendina cassetto del QuickAdd scorre invece di spingere.
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(campi.enumerated()), id: \.offset) { i, campo in
                            Button { copiaTesto(campo.valore) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: campo.icona)
                                        .font(.system(size: 12))
                                        .frame(width: 16)
                                        .foregroundStyle(Theme.inkSoft)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(campo.nome)
                                            .font(Theme.mono(11))
                                            .foregroundStyle(Theme.inkSoft)
                                        Text(campo.nome == "Password" ? String(repeating: "•", count: 8) : campo.valore)
                                            .font(Theme.mono(13, .semibold))
                                            .foregroundStyle(Theme.ink)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.inkSoft)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: Self.altezzaRiga)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if i != campi.count - 1 {
                                Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 1)
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(campi.count) * Self.altezzaRiga, Self.altezzaRiga * CGFloat(Self.massimoRisultati)))
                .background(Theme.paper)
            }
        }
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1.2))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    private func avviaCaricamento() {
        cercaAttivo = true
        Task { await VaultLibrary.shared.preload(VaultFileManager.shared.projects) }
    }

    private func copiaTesto(_ testo: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(testo, forType: .string)
        onDone()
    }

    private func copia(_ match: Match?) {
        guard let match else { return }
        copiaTesto(match.entry.password)
    }
}

// MARK: - Master password (solo senza Touch ID)

private struct PasswordRapidaRicerca: View {
    let onSbloccato: () -> Void
    let onAnnulla: () -> Void

    @State private var password = ""
    @State private var errore: String?

    var body: some View {
        VStack(spacing: 12) {
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
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1.2))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
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
