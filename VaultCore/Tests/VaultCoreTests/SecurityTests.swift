import XCTest
@testable import VaultCore

/// Prove d'attacco sul formato: quel che un malintenzionato proverebbe avendo
/// in mano il file .kdbx e nient'altro.
final class SecurityTests: XCTestCase {

    private func makeVault(password: String) throws -> [UInt8] {
        let db = VaultDatabase.createNew(name: "prova")
        db.addEntry(VaultEntry(title: "banca", username: "mario",
                               password: "SegretoAssoluto123!", url: "https://banca.it",
                               notes: "riservato"))
        return try Kdbx4.save(database: db, password: password)
    }

    /// Il segreto non deve comparire in chiaro da nessuna parte nel file.
    func testNienteInChiaroNelFile() throws {
        let bytes = try makeVault(password: "chiave-lunga-e-robusta")
        let blob = Data(bytes)
        for segreto in ["SegretoAssoluto123!", "mario", "banca.it", "riservato"] {
            XCTAssertNil(blob.range(of: Data(segreto.utf8)),
                         "«\(segreto)» si legge in chiaro dentro al .kdbx")
        }
    }

    /// Password sbagliate: sempre respinte, nessuna eccezione.
    func testPasswordSbagliateRespinte() throws {
        let bytes = try makeVault(password: "chiave-lunga-e-robusta")
        for tentativo in ["", " ", "chiave-lunga-e-robust", "chiave-lunga-e-robusta ",
                          "CHIAVE-LUNGA-E-ROBUSTA", "password", "1234"] {
            XCTAssertThrowsError(try Kdbx4.open(data: bytes, password: tentativo),
                                 "aperto con «\(tentativo)»")
        }
    }

    /// La password giusta apre, e restituisce i dati intatti.
    func testPasswordGiustaApre() throws {
        let bytes = try makeVault(password: "chiave-lunga-e-robusta")
        let db = try Kdbx4.open(data: bytes, password: "chiave-lunga-e-robusta")
        XCTAssertEqual(db.allEntries.first?.password, "SegretoAssoluto123!")
    }

    /// File manomesso: va rifiutato, non aperto a metà. Senza questo controllo
    /// si potrebbe alterare un vault senza conoscerne la password.
    func testFileManomessoRifiutato() throws {
        var bytes = try makeVault(password: "chiave-lunga-e-robusta")
        bytes[bytes.count - 40] ^= 0xFF   // un bit nel corpo cifrato
        XCTAssertThrowsError(try Kdbx4.open(data: bytes, password: "chiave-lunga-e-robusta"),
                             "un vault manomesso è stato aperto lo stesso")
    }

    /// Due salvataggi della stessa password devono dare file diversi: se il
    /// sale fosse fisso, si potrebbero precalcolare le chiavi.
    func testSaleSempreDiverso() throws {
        let a = try makeVault(password: "stessa-password")
        let b = try makeVault(password: "stessa-password")
        XCTAssertNotEqual(Data(a).prefix(200), Data(b).prefix(200))
    }

    /// I campi liberi marcati come protetti non devono finire in chiaro.
    func testCampiProtettiCifrati() throws {
        let db = VaultDatabase.createNew(name: "carte")
        db.addEntry(VaultEntry(title: "visa", customFields: [
            VaultCustomField(key: "numero carta", value: "4111111111111111", isProtected: true)
        ]))
        let bytes = try Kdbx4.save(database: db, password: "chiave-lunga-e-robusta")
        XCTAssertNil(Data(bytes).range(of: Data("4111111111111111".utf8)),
                     "il numero di carta si legge in chiaro")

        let riletto = try Kdbx4.open(data: bytes, password: "chiave-lunga-e-robusta")
        XCTAssertEqual(riletto.allEntries.first?.custom("numero carta"), "4111111111111111")
    }
}
