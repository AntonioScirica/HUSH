import Foundation

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
        groupPath: String = ""
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
