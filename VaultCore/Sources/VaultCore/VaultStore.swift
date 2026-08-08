import Foundation
import Combine

public enum VaultStoreError: Error, LocalizedError {
    case notOpen
    public var errorDescription: String? {
        switch self {
        case .notOpen: return "Nessun vault aperto."
        }
    }
}

/// Punto di ingresso ad alto livello di VaultCore: apertura/creazione/salvataggio
/// del database e operazioni CRUD sulle voci. Le operazioni di apertura e
/// salvataggio sono asincrone perché Argon2id è volutamente lento (~0.3–1s
/// per progettazione, è quello che rende il brute-force costoso).
public final class VaultStore: ObservableObject {
    @Published public private(set) var database: VaultDatabase?
    @Published public private(set) var isUnlocked: Bool = false

    private var password: String?
    private var keyfile: [UInt8]?

    public init() {}

    public func createNew(name: String, password: String) {
        database = VaultDatabase.createNew(name: name)
        self.password = password
        self.keyfile = nil
        isUnlocked = true
    }

    public func open(fileData: [UInt8], password: String, keyfile: [UInt8]? = nil) async throws {
        let db = try await Task.detached(priority: .userInitiated) {
            try Kdbx4.open(data: fileData, password: password, keyfile: keyfile)
        }.value
        await MainActor.run {
            self.database = db
            self.password = password
            self.keyfile = keyfile
            self.isUnlocked = true
        }
    }

    public func save() async throws -> [UInt8] {
        guard let db = database, let pw = password else { throw VaultStoreError.notOpen }
        let kf = keyfile
        return try await Task.detached(priority: .userInitiated) {
            try Kdbx4.save(database: db, password: pw, keyfile: kf)
        }.value
    }

    /// Cambia la master password che verrà usata dal prossimo `save()`.
    public func setMasterPassword(_ newPassword: String) {
        password = newPassword
    }

    public func lock() {
        database = nil
        password = nil
        keyfile = nil
        isUnlocked = false
    }

    public func addEntry(_ entry: VaultEntry) {
        database?.addEntry(entry)
        objectWillChange.send()
    }

    public func updateEntry(_ entry: VaultEntry) {
        database?.updateEntry(entry)
        objectWillChange.send()
    }

    public func deleteEntry(id: UUID) {
        database?.deleteEntry(id: id)
        objectWillChange.send()
    }

    public var allEntries: [VaultEntry] {
        database?.allEntries ?? []
    }
}
