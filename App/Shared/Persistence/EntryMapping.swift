import Foundation
import VaultCore

/// Traduzione fra le voci dell'app e quelle del file KDBX.
///
/// Login e password ci stanno dentro senza forzature: utente, password, url e
/// note sono campi canonici del formato. Gli altri tipi (carta, identità,
/// note, documento) usano i campi liberi, che il KDBX prevede: restano
/// leggibili anche aprendo il file con KeePass, invece di finire impastati
/// dentro alle note.
enum EntryMapping {
    /// Chiave in cui si annota di che tipo è la voce. Il prefisso evita di
    /// pestare i piedi ai campi di altri programmi.
    static let kindKey = "scrigno.kind"

    /// Campi il cui valore va cifrato dentro al file: numero di carta, cvv,
    /// pin e simili non devono stare in chiaro nell'XML.
    private static let secretKeys: Set<String> = [
        "numero carta", "cvv", "pin", "codice fiscale", "iban",
        // la chiave di un allegato apre il documento: va protetta come una password
        "scrigno.allegato.chiave"
    ]

    static func isSecret(_ key: String) -> Bool {
        secretKeys.contains(key.lowercased())
    }

    // MARK: - App → KDBX

    /// Voce con credenziali (accesso, password): campi canonici più gli extra.
    static func credentialEntry(
        id: UUID = UUID(),
        kind: String,
        title: String,
        user: String,
        password: String,
        url: String,
        notes: String,
        extras: [(label: String, value: String)]
    ) -> VaultEntry {
        VaultEntry(
            id: id, title: title, username: user, password: password,
            url: url, notes: notes,
            customFields: [VaultCustomField(key: kindKey, value: kind)]
                + extras.map {
                    VaultCustomField(key: $0.label, value: $0.value, isProtected: isSecret($0.label))
                }
        )
    }

    /// Voce senza credenziali (nota, carta, identità, documento): tutto nei
    /// campi liberi, nell'ordine in cui l'utente li ha scritti.
    static func detailEntry(
        id: UUID = UUID(),
        kind: String,
        title: String,
        fields: [(label: String, value: String)]
    ) -> VaultEntry {
        VaultEntry(
            id: id, title: title,
            customFields: [VaultCustomField(key: kindKey, value: kind)]
                + fields.map {
                    VaultCustomField(key: $0.label, value: $0.value, isProtected: isSecret($0.label))
                }
        )
    }

    // MARK: - KDBX → App

    static func kind(of entry: VaultEntry) -> String {
        // Senza l'annotazione — per esempio una voce arrivata da un altro
        // programma — si guarda cosa contiene: se ha una password è un accesso.
        entry.custom(kindKey) ?? (entry.password.isEmpty ? "secureNote" : "login")
    }

    /// I campi liberi da mostrare.
    ///
    /// Quelli con prefisso `scrigno.` sono roba di servizio — il tipo della
    /// voce, il percorso e la chiave di un allegato — e non vanno né mostrati
    /// né, tantomeno, copiati: la chiave dell'allegato a schermo sarebbe come
    /// scrivere la password sul post-it.
    static func details(of entry: VaultEntry) -> [(label: String, value: String)] {
        entry.customFields
            .filter { !$0.key.hasPrefix("scrigno.") }
            .map { (label: $0.key, value: $0.value) }
    }

    /// I campi di servizio, da riportare intatti quando si risalva una voce:
    /// ricostruendola dai soli campi visibili si perderebbe l'allegato.
    static func hiddenFields(of entry: VaultEntry) -> [VaultCustomField] {
        entry.customFields.filter { $0.key.hasPrefix("scrigno.") && $0.key != kindKey }
    }
}
