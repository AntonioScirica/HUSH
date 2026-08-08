import XCTest
@testable import VaultCore

/// Questi test servono soprattutto come "prova del nove" da eseguire con
/// `swift test` prima ancora di aprire Xcode: se passano tutti, la
/// crittografia di base (ChaCha20, CRC32, Argon2id) e la lettura di un vault
/// KDBX4 reale funzionano correttamente su questo Mac.
///
/// I valori attesi in questi test NON sono stati inventati: sono stati
/// calcolati con implementazioni indipendenti e affidabili (PyCryptodome,
/// zlib, argon2-cffi — lo stesso codice C vendorizzato qui) durante lo
/// sviluppo, prima di scrivere il codice Swift corrispondente.
final class VaultCoreTests: XCTestCase {

    func testChaCha20KnownVector() {
        let key = Array(hex: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
        let nonce = Array(hex: "6465666768696a6b6c6d6e6f")
        let plaintext = Array("Scrigno - vettore di test ChaCha20, validato contro pycryptodome.".utf8)
        let expected = "bcb9414beaae7846968bdef713fba6b6997f01fce06e137968515a6772256bbe48bedfe09463eacd5d587e8ecefd19d1143bee0e3e6352286f6c7c61c778f66b1a"
        let ct = ChaCha20.xor(key: key, counter: 0, nonce: nonce, data: plaintext)
        XCTAssertEqual(ct.hexString, expected)
        // e deve essere invertibile
        let back = ChaCha20.xor(key: key, counter: 0, nonce: nonce, data: ct)
        XCTAssertEqual(back, plaintext)
    }

    func testCRC32KnownVectors() {
        XCTAssertEqual(CRC32.checksum([]), 0)
        let quickFox = Array("The quick brown fox jumps over the lazy dog".utf8)
        XCTAssertEqual(CRC32.checksum(quickFox), 0x414f_a339)
    }

    func testArgon2idKnownVector() throws {
        let password = Array("scrigno-test-password".utf8)
        let salt = Array(hex: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
        let expected = "11cb6f94cc5306e18ef539db21fb188bfcf43e7b53d79340a2745742d5f5d1f4"
        let out = try Argon2.hash(
            password: password, salt: salt,
            iterations: 2, memoryKiB: 8 * 1024, parallelism: 1,
            outputLength: 32, kind: .argon2id, version: 0x13
        )
        XCTAssertEqual(out.hexString, expected)
    }

    func testGZipRoundTrip() throws {
        let original = Array(String(repeating: "Scrigno vault di prova. ", count: 200).utf8)
        let compressed = try GZip.compress(original)
        XCTAssertLessThan(compressed.count, original.count)
        let decompressed = try GZip.decompress(compressed)
        XCTAssertEqual(decompressed, original)
    }

    func testCreateSaveReopenRoundTrip() async throws {
        let db = VaultDatabase.createNew(name: "Vault di prova")
        db.addEntry(VaultEntry(title: "GitHub", username: "antonio", password: "Sup3rSegreta!", url: "https://github.com"))
        db.addEntry(VaultEntry(title: "Posta", username: "as.scirica@gmail.com", password: "Altra$$Password9", url: "https://mail.google.com"))

        let saved = try Kdbx4.save(database: db, password: "master-password-di-prova-123!")
        let reopened = try Kdbx4.open(data: saved, password: "master-password-di-prova-123!")

        let titles = Set(reopened.allEntries.map(\.title))
        XCTAssertEqual(titles, ["GitHub", "Posta"])
        let github = reopened.allEntries.first { $0.title == "GitHub" }
        XCTAssertEqual(github?.password, "Sup3rSegreta!")
        XCTAssertEqual(github?.username, "antonio")

        // master password sbagliata deve fallire in modo pulito, non con un crash
        XCTAssertThrowsError(try Kdbx4.open(data: saved, password: "sbagliata")) { error in
            XCTAssertEqual(error as? Kdbx4Error, .invalidPassword)
        }
    }

    /// Il vault qui sotto (base64) è stato creato e verificato durante lo
    /// sviluppo con TRE implementazioni indipendenti (la web-app Scrigno.html
    /// basata su kdbxweb, un prototipo Python, e pykeepass) prima di essere
    /// congelato come test di regressione: se questo test passa, VaultCore
    /// legge correttamente i vault KDBX4 reali creati da altri programmi.
    func testOpenRealWorldVault() async throws {
        let data = Array(Data(base64Encoded: Self.realVaultBase64, options: .ignoreUnknownCharacters)!)
        let db = try Kdbx4.open(data: data, password: "una-frase-lunga-e-sicura-2026!")
        let titles = Set(db.allEntries.map(\.title))
        XCTAssertEqual(titles, ["Gmail", "Amazon"])
        let gmail = db.allEntries.first { $0.title == "Gmail" }
        XCTAssertEqual(gmail?.password, "Pr0va!Sicura#2026xyz")
        XCTAssertEqual(gmail?.username, "as.scirica@gmail.com")
    }

    private static let realVaultBase64 = "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"
}

private extension Array where Element == UInt8 {
    init(hex: String) {
        var bytes: [UInt8] = []
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            bytes.append(UInt8(hex[idx..<next], radix: 16)!)
            idx = next
        }
        self = bytes
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

extension Kdbx4Error: Equatable {
    public static func == (lhs: Kdbx4Error, rhs: Kdbx4Error) -> Bool {
        switch (lhs, rhs) {
        case (.invalidPassword, .invalidPassword): return true
        case (.badSignature, .badSignature): return true
        default: return "\(lhs)" == "\(rhs)"
        }
    }
}
