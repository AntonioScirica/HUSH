import Foundation

/// Campo libero di una voce, oltre ai cinque canonici.
///
/// Il KDBX non ha un elenco chiuso di campi: una voce è una lista di coppie
/// chiave/valore, e Title, UserName, Password, URL e Notes sono soltanto
/// quelle che tutti i programmi conoscono. Qui stanno le altre — i dati di
/// una carta, di un documento d'identità — che così restano leggibili anche
/// aprendo il file con KeePass o strumenti simili.
public struct VaultCustomField: Equatable, Hashable {
    public var key: String
    public var value: String
    /// Cifrato dentro al file, come la password.
    public var isProtected: Bool

    public init(key: String, value: String, isProtected: Bool = false) {
        self.key = key
        self.value = value
        self.isProtected = isProtected
    }
}

public struct VaultEntry: Identifiable, Equatable, Hashable {
    public var id: UUID
    public var title: String
    public var username: String
    public var password: String
    public var url: String
    public var notes: String
    public var iconId: Int
    public var created: Date
    public var modified: Date
    /// Percorso del gruppo di appartenenza, solo per la visualizzazione (es. "Lavoro / Email").
    public var groupPath: String
    /// Campi oltre ai cinque canonici, nell'ordine in cui li ha messi l'utente.
    public var customFields: [VaultCustomField]

    public init(
        id: UUID = UUID(),
        title: String,
        username: String = "",
        password: String = "",
        url: String = "",
        notes: String = "",
        iconId: Int = 0,
        created: Date = Date(),
        modified: Date = Date(),
        groupPath: String = "",
        customFields: [VaultCustomField] = []
    ) {
        self.id = id
        self.title = title
        self.username = username
        self.password = password
        self.url = url
        self.notes = notes
        self.iconId = iconId
        self.created = created
        self.modified = modified
        self.groupPath = groupPath
        self.customFields = customFields
    }

    /// Valore di un campo libero, se c'è.
    public func custom(_ key: String) -> String? {
        customFields.first { $0.key == key }?.value
    }
}

/// Un gruppo (cartella) del vault, con eventuali sottogruppi — riflette la
/// struttura ad albero del formato KDBX.
public final class VaultGroup {
    public var id: UUID
    public var name: String
    public var entries: [VaultEntry] = []
    public var subgroups: [VaultGroup] = []
    public var isRecycleBin: Bool = false

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    /// Tutte le voci del sottoalbero, in ordine di visita, escluso il cestino.
    public func flattenEntries(pathPrefix: String = "") -> [VaultEntry] {
        var out: [VaultEntry] = []
        if isRecycleBin { return out }
        let myPath = pathPrefix
        for e in entries {
            var entry = e
            entry.groupPath = myPath
            out.append(entry)
        }
        for g in subgroups {
            let childPath = myPath.isEmpty ? g.name : "\(myPath) / \(g.name)"
            out.append(contentsOf: g.flattenEntries(pathPrefix: childPath))
        }
        return out
    }
}

/// Il database in memoria: nome, gruppo radice, e i parametri di sicurezza
/// (KDF, seed, ecc.) necessari per un successivo salvataggio compatibile.
public final class VaultDatabase {
    public var name: String
    public var root: VaultGroup

    public init(name: String, root: VaultGroup) {
        self.name = name
        self.root = root
    }

    public static func createNew(name: String) -> VaultDatabase {
        let root = VaultGroup(name: "Root")
        let recycleBin = VaultGroup(name: "Recycle Bin")
        recycleBin.isRecycleBin = true
        root.subgroups.append(recycleBin)
        return VaultDatabase(name: name, root: root)
    }

    public var allEntries: [VaultEntry] {
        root.flattenEntries()
    }

    /// Aggiunge una nuova voce al gruppo radice (fuori dal cestino).
    public func addEntry(_ entry: VaultEntry) {
        root.entries.append(entry)
    }

    public func updateEntry(_ entry: VaultEntry) {
        if updateEntry(entry, in: root) { return }
    }

    @discardableResult
    private func updateEntry(_ entry: VaultEntry, in group: VaultGroup) -> Bool {
        if let idx = group.entries.firstIndex(where: { $0.id == entry.id }) {
            group.entries[idx] = entry
            return true
        }
        for g in group.subgroups {
            if updateEntry(entry, in: g) { return true }
        }
        return false
    }

    public func deleteEntry(id: UUID) {
        _ = deleteEntry(id: id, in: root)
    }

    @discardableResult
    private func deleteEntry(id: UUID, in group: VaultGroup) -> Bool {
        if let idx = group.entries.firstIndex(where: { $0.id == id }) {
            group.entries.remove(at: idx)
            return true
        }
        for g in group.subgroups {
            if deleteEntry(id: id, in: g) { return true }
        }
        return false
    }
}
