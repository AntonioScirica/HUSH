import XCTest
import CryptoKit

/// Prove sulla licenza: la logica di verifica è replicata qui perché License
/// vive nel target dell'app. La licenza sotto è stata emessa davvero dallo
/// script del server con la chiave privata vera.
final class LicenseTests: XCTestCase {
    private let publicKeyBase64 = "WRxxNOQWk/5qT1+I+BPQ1qVIRdg8ZshDUkVMOvlKpK0="
    private let licenzaVera = "eyJlbWFpbCI6ImNsaWVudGVAZXNlbXBpby5pdCIsInBsYW4iOiJ2aXRhIiwiaXNzdWVkIjoxNzg2MjQwODYxfQ.AlPyJiGzn0qyITKMTOFuCwMg1Dgx-8KxQ6ati2qYyyUfL3gRKXu-ajHr9iQuBRLl_2RgsaYJZKzlKBGLCpOeBw"

    private func b64url(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t.append("=") }
        return Data(base64Encoded: t)
    }

    private func verifica(_ raw: String) -> [String: Any]? {
        let parts = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payload = b64url(String(parts[0])),
              let firma = b64url(String(parts[1])),
              let keyData = Data(base64Encoded: publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              key.isValidSignature(firma, for: payload)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
    }

    /// Una licenza emessa dal server viene accettata, coi dati giusti.
    func testLicenzaVeraAccettata() throws {
        let info = try XCTUnwrap(verifica(licenzaVera))
        XCTAssertEqual(info["email"] as? String, "cliente@esempio.it")
        XCTAssertEqual(info["plan"] as? String, "vita")
    }

    /// Cambiare l'email nella licenza — il trucco più ovvio, per passarla a
    /// un altro — invalida la firma.
    func testEmailAlteratsRespinta() throws {
        let parts = licenzaVera.split(separator: ".", maxSplits: 1)
        var json = try XCTUnwrap(b64url(String(parts[0])).flatMap { String(data: $0, encoding: .utf8) })
        json = json.replacingOccurrences(of: "cliente@esempio.it", with: "pirata@esempio.it")
        let rifatta = Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertNil(verifica("\(rifatta).\(parts[1])"), "licenza alterata accettata")
    }

    /// Una licenza inventata di sana pianta non passa.
    func testLicenzaInventataRespinta() {
        let payload = Data(#"{"email":"finto@esempio.it","plan":"vita","issued":1}"#.utf8)
            .base64EncodedString()
        let firma = Data(repeating: 0x42, count: 64).base64EncodedString()
        XCTAssertNil(verifica("\(payload).\(firma)"))
    }

    /// Firma di un'altra coppia di chiavi: respinta.
    func testFirmaDiAltraChiaveRespinta() throws {
        let altra = Curve25519.Signing.PrivateKey()
        let payload = Data(#"{"email":"x@y.it","plan":"vita","issued":1}"#.utf8)
        let firma = try altra.signature(for: payload)
        let a = payload.base64EncodedString().replacingOccurrences(of: "=", with: "")
        let b = firma.base64EncodedString().replacingOccurrences(of: "=", with: "")
        XCTAssertNil(verifica("\(a).\(b)"))
    }

    /// Spazzatura varia: nessun crash, solo rifiuto.
    func testSpazzaturaRespinta() {
        for s in ["", ".", "a.b", "senza-punto", String(repeating: "x", count: 500)] {
            XCTAssertNil(verifica(s), "accettato «\(s)»")
        }
    }
}
