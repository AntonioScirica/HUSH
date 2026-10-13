import AppIntents
import VaultCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Intent per Comandi Rapidi: invece di scrivere la password a mano nello
/// shortcut, la si cerca fra le voci di Hush e si copia negli appunti.
/// L'autenticazione di sistema ("Richiedi Touch ID o password") resta un
/// passo separato che l'utente aggiunge da sé nello shortcut, prima di
/// questo: qui serve solo a sbloccare la sessione di Hush se non è già
/// aperta, non sostituisce quel gate.
enum IntentAuth {
    /// La master password della sessione corrente, sbloccando col dito se
    /// serve. `nil` se Hush non è configurato o il dito non è attivo — in
    /// quel caso va aperto Hush e sbloccato a mano prima di rilanciare lo shortcut.
    static func session() async -> String? {
        if let session = MasterKey.session { return session }
        guard MasterKey.biometryUsable else { return nil }
        return await withCheckedContinuation { continuation in
            MasterKey.unlockWithBiometry { _ in
                continuation.resume(returning: MasterKey.session)
            }
        }
    }
}

/// Una voce del vault, per il menu di ricerca dello shortcut.
struct EntryEntity: AppEntity, Identifiable {
    let id: String                 // "percorso-progetto::uuid-voce"
    let title: String
    let projectName: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Voce Hush"
    static var defaultQuery = EntryQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(projectName)")
    }
}

struct EntryQuery: EntityStringQuery {
    func entities(for identifiers: [EntryEntity.ID]) async throws -> [EntryEntity] {
        let tutte = await Self.tutteLeVoci()
        return tutte.filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [EntryEntity] {
        let tutte = try await Self.tutteLeVociOFallisci()
        guard !string.isEmpty else { return Array(tutte.prefix(20)) }
        let q = string.lowercased()
        return tutte.filter { $0.title.lowercased().contains(q) }
    }

    func suggestedEntities() async throws -> [EntryEntity] {
        Array(try await Self.tutteLeVociOFallisci().prefix(20))
    }

    /// Come `tutteLeVoci()`, ma segnala il perché invece di tornare una
    /// lista vuota: senza sessione lo shortcut sembrava fare "nada".
    static func tutteLeVociOFallisci() async throws -> [EntryEntity] {
        guard await IntentAuth.session() != nil else {
            throw IntentError.message("Apri Hush e sbloccalo (o attiva Touch ID nelle Impostazioni di Hush), poi riprova.")
        }
        return await tutteLeVoci()
    }

    /// Solo i titoli, decifrati una volta e non più segreti di quanto già
    /// non lo siano nella lista dell'app: la password vera si decifra solo
    /// al momento della copia, dentro l'intent.
    static func tutteLeVoci() async -> [EntryEntity] {
        guard let key = await IntentAuth.session() else { return [] }
        var risultato: [EntryEntity] = []
        for project in VaultFileManager.shared.projects {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: project.path)),
                  let db = try? Kdbx4.open(data: Array(data), password: key)
            else { continue }
            for entry in db.allEntries {
                risultato.append(EntryEntity(
                    id: "\(project.path)::\(entry.id.uuidString)",
                    title: entry.title.isEmpty ? "senza titolo" : entry.title,
                    projectName: project.name
                ))
            }
        }
        return risultato
    }
}

struct CopiaPasswordIntent: AppIntent {
    static var title: LocalizedStringResource = "Cerca e copia password"
    static var description = IntentDescription("Cerca una voce in Hush e copia la sua password negli appunti.")

    @Parameter(title: "Voce")
    var voce: EntryEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Copia la password di \(\.$voce)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let key = await IntentAuth.session() else {
            throw IntentError.message("Sblocca Hush (Touch ID o master password) e riprova.")
        }
        let parti = voce.id.components(separatedBy: "::")
        guard parti.count == 2,
              let uuid = UUID(uuidString: parti[1]),
              let data = try? Data(contentsOf: URL(fileURLWithPath: parti[0])),
              let db = try? Kdbx4.open(data: Array(data), password: key),
              let entry = db.allEntries.first(where: { $0.id == uuid })
        else {
            throw IntentError.message("Non trovo più questa voce.")
        }

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.password, forType: .string)
        #else
        UIPasteboard.general.string = entry.password
        #endif

        return .result(dialog: "Password di «\(entry.title)» copiata.")
    }
}

enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case message(String)
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .message(let m): return LocalizedStringResource(stringLiteral: m)
        }
    }
}

struct HushShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CopiaPasswordIntent(),
            phrases: ["Cerca password in \(.applicationName)"],
            shortTitle: "Cerca password",
            systemImageName: "key"
        )
    }
}
