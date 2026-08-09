import Foundation
import CryptoKit
#if os(macOS)
import IOKit
#else
import UIKit
#endif

/// Licenza d'uso: dice se il prodotto è stato pagato. Niente a che vedere con
/// la chiave di recupero, che invece apre i vault — questa non decifra niente.
///
/// Come funziona: il server firma i dati della licenza con una chiave privata
/// Ed25519; l'app li verifica con la chiave pubblica, che sta qui sotto. La
/// verifica è matematica, quindi **funziona senza rete**: nessuna chiamata a
/// casa, nessun server da tenere in piedi, nessun modo di sapere chi apre
/// l'app e quando. Per un gestore di password locale è l'unica forma
/// accettabile: un controllo online sarebbe un guinzaglio, e un guasto del
/// server lascerebbe la gente fuori dalle proprie password.
///
/// Formato della licenza (come un mini-JWT, senza intestazione):
///     base64url(json) + "." + base64url(firma)
///
/// Il json contiene almeno: `email`, `plan`, `issued`. Volendo `expires`.
enum License {
    /// Chiave pubblica di firma. La privata sta sul server che emette le
    /// licenze: chi ce l'ha può fabbricarne di valide.
    private static let publicKeyBase64 = "7fXzi+lxmJxcIlMx1FO5buQ2ZXOb+kyqSpWSKKdZ75E="

    private static let licenseKey = "scrigno.license"
    private static let firstRunKey = "scrigno.firstRun"
    private static let deviceKey = "scrigno.license.device"

    /// Giorni di prova prima che la licenza diventi necessaria.
    static let trialDays = 7

    /// Identificativo di questa macchina: il numero di serie della scheda,
    /// che non cambia reinstallando il sistema.
    static var deviceID: String {
        #if os(macOS)

        let entry = IOServiceGetMatchingService(kIOMainPortDefault,
                                                IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(entry) }
        guard entry != 0,
              let cf = IORegistryEntryCreateCFProperty(entry, kIOPlatformUUIDKey as CFString,
                                                       kCFAllocatorDefault, 0),
              let uuid = cf.takeRetainedValue() as? String
        else { return "sconosciuto" }
        return uuid
    
        #else
        // identificatore stabile finché l'app resta installata: per legare
        // la licenza basta e avanza, e non tocca niente di personale
        return UIDevice.current.identifierForVendor?.uuidString ?? "sconosciuto"
        #endif
    }

    struct Info: Codable, Equatable {
        var email: String
        var plan: String
        /// Secondi dal 1970. Usiamo un numero e non una data formattata: le
        /// date scritte a parole cambiano forma da un fuso all'altro.
        var issued: Double
        var expires: Double?

        var isExpired: Bool {
            guard let expires else { return false }   // senza scadenza: a vita
            return Date().timeIntervalSince1970 > expires
        }
    }

    // MARK: - Stato

    /// Licenza registrata, valida e legata a QUESTA macchina.
    ///
    /// Il legame è locale: la licenza vale per un computer, e per usarla su un
    /// altro va prima staccata da qui. Senza un server non si può impedire a
    /// qualcuno di attivarla anche altrove — si può però rendere ovvia e
    /// comoda la strada onesta, che è quella che quasi tutti prendono.
    static var active: Info? {
        guard let raw = UserDefaults.standard.string(forKey: licenseKey),
              let info = verify(raw), !info.isExpired,
              UserDefaults.standard.string(forKey: deviceKey) == deviceID
        else { return nil }
        return info
    }

    /// Stacca la licenza da questo computer, per poterla attivare su un altro.
    static func detach() {
        UserDefaults.standard.removeObject(forKey: licenseKey)
        UserDefaults.standard.removeObject(forKey: deviceKey)
    }

    static var isLicensed: Bool { active != nil }

    /// Primo avvio, per il conto della prova. Si segna alla prima lettura.
    static var firstRun: Date {
        let stored = UserDefaults.standard.double(forKey: firstRunKey)
        if stored > 0 { return Date(timeIntervalSince1970: stored) }
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: firstRunKey)
        return now
    }

    static var trialDaysLeft: Int {
        let elapsed = Date().timeIntervalSince(firstRun) / 86_400
        return max(0, trialDays - Int(elapsed))
    }

    /// In prova o pagata: l'app si può usare.
    static var isUsable: Bool { isLicensed || trialDaysLeft > 0 }

    // MARK: - Registrazione

    /// Registra una licenza incollata dall'utente. Ritorna `nil` se la firma
    /// non torna: significa che è stata inventata o modificata.
    @discardableResult
    static func register(_ raw: String) -> Info? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let info = verify(cleaned), !info.isExpired else { return nil }
        UserDefaults.standard.set(cleaned, forKey: licenseKey)
        UserDefaults.standard.set(deviceID, forKey: deviceKey)
        return info
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: licenseKey)
    }

    // MARK: - Verifica

    /// Controlla la firma e restituisce i dati, se sono autentici.
    static func verify(_ raw: String) -> Info? {
        let parts = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payload = base64urlDecode(String(parts[0])),
              let signature = base64urlDecode(String(parts[1])),
              let keyData = Data(base64Encoded: publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              // la firma copre i byte del payload così com'è: verificarla su
              // un json ri-serializzato fallirebbe al primo spazio diverso
              key.isValidSignature(signature, for: payload)
        else { return nil }
        return try? JSONDecoder().decode(Info.self, from: payload)
    }

    /// Base64 "url-safe": è quella che si può incollare senza che un client di
    /// posta o una barra degli indirizzi le storpi i caratteri.
    private static func base64urlDecode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t.append("=") }
        return Data(base64Encoded: t)
    }
}
