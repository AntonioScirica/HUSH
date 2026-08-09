import XCTest
import CryptoKit

/// Prove sulla chiave di recupero, replicando qui la stessa logica dell'app
/// (RecoveryKit vive nel target dell'app, non nel pacchetto).
final class RecoveryLogicTests: XCTestCase {
    private let alphabet = Array("23456789ACDEFGHJKMNPQRTUVWXYZ")

    private func normalize(_ k: String) -> String {
        k.uppercased().filter { alphabet.contains($0) }
    }

    private func symKey(_ key: String, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(normalize(key).utf8)),
            salt: salt, info: Data("scrigno.recovery".utf8), outputByteCount: 32
        )
    }

    private func makeKit(master: String) -> (key: String, blob: Data) {
        var key = ""
        for i in 0..<30 {
            if i > 0 && i % 5 == 0 { key.append("-") }
            key.append(alphabet[Int.random(in: 0..<alphabet.count)])
        }
        var s = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &s)
        let salt = Data(s)
        let sealed = try! AES.GCM.seal(Data(master.utf8), using: symKey(key, salt: salt))
        return (key, salt + sealed.combined!)
    }

    private func recover(_ key: String, blob: Data) throws -> String {
        let salt = blob.prefix(32)
        let box = try AES.GCM.SealedBox(combined: blob.dropFirst(32))
        let plain = try AES.GCM.open(box, using: symKey(key, salt: salt))
        return String(data: plain, encoding: .utf8)!
    }

    /// La chiave giusta restituisce la master password esatta.
    func testChiaveGiustaRecupera() throws {
        let kit = makeKit(master: "la-mia-password-lunghissima")
        XCTAssertEqual(try recover(kit.key, blob: kit.blob), "la-mia-password-lunghissima")
    }

    /// Scritta senza trattini o in minuscolo funziona lo stesso: chi la
    /// ricopia dalla carta non deve azzeccare anche la punteggiatura.
    func testTolleranteAFormatoEMaiuscole() throws {
        let kit = makeKit(master: "segreto")
        let sciolta = kit.key.replacingOccurrences(of: "-", with: "").lowercased()
        XCTAssertEqual(try recover(sciolta, blob: kit.blob), "segreto")
    }

    /// Chiavi sbagliate: sempre respinte, anche a un carattere di distanza.
    func testChiaviSbagliateRespinte() {
        let kit = makeKit(master: "segreto")
        var quasi = Array(normalize(kit.key))
        quasi[0] = quasi[0] == "2" ? "3" : "2"
        for tentativo in [String(quasi), "", "AAAAA-AAAAA-AAAAA-AAAAA-AAAAA-AAAAA"] {
            XCTAssertThrowsError(try recover(tentativo, blob: kit.blob),
                                 "recuperato con «\(tentativo)»")
        }
    }

    /// Il file di recupero da solo non dice niente: la password non ci si
    /// legge dentro in chiaro.
    func testBlobNonRivelaLaPassword() {
        let kit = makeKit(master: "password-in-chiaro-cercami")
        XCTAssertNil(kit.blob.range(of: Data("password-in-chiaro-cercami".utf8)))
    }

    /// File manomesso: rifiutato, non restituito corrotto.
    func testBlobManomessoRifiutato() {
        let kit = makeKit(master: "segreto")
        var rotto = kit.blob
        rotto[rotto.count - 5] ^= 0xFF
        XCTAssertThrowsError(try recover(kit.key, blob: rotto))
    }

    /// Due chiavi generate di fila non si somigliano.
    func testChiaviSempreDiverse() {
        let a = makeKit(master: "x").key, b = makeKit(master: "x").key
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(normalize(a).count, 30)   // 30 simboli su 29 ≈ 145 bit
    }
}
