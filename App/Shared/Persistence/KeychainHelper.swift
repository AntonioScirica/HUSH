import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case unhandled(OSStatus)
    case notFound
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unhandled(let status): return "Errore Keychain (\(status))."
        case .notFound: return "Nessuna password salvata."
        case .encodingFailed: return "Errore interno di codifica."
        }
    }
}

/// Salva la master password nel Portachiavi.
///
/// Su iOS l'elemento è protetto da Face ID/Touch ID (`biometryCurrentSet`):
/// il sistema chiede la biometria a ogni lettura. App ed estensione AutoFill
/// dichiarano lo STESSO `keychain-access-groups`, quindi senza specificare
/// `kSecAttrAccessGroup` iOS usa il (solo) gruppo dichiarato, condiviso.
///
/// Su macOS l'elemento sta nel portachiavi "Data Protection" (lo stesso che
/// il bridge usa già per il suo token): l'accesso è legato all'entitlement
/// `keychain-access-groups`, NON alla firma della singola build. Prima stava
/// nel portachiavi "login" con una ACL sulla firma: a ogni build firmata
/// diversamente (test vs release) macOS vedeva "un'altra app" e chiedeva la
/// password di sistema a ogni sblocco — il pannello grigio che non moriva mai.
/// La biometria su macOS la gestisce l'app con LAContext prima di leggere.
enum SharedKeychain {
    private static let service = "com.antonioscirica.scrigno.masterpassword"
    private static let account = "vault"
    #if os(macOS)
    /// Stesso gruppo del bridge: è l'unico dichiarato nelle entitlements
    /// del target macOS, e per questo elemento va indicato esplicitamente.
    private static let accessGroup = "69SHH7M6DY.com.antonioscirica.hush.bridge"

    private static func query(_ extra: [String: Any] = [:]) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessGroup as String: accessGroup,
            // Service DIVERSO da quello vecchio, apposta: le query "legacy"
            // (senza flag Data Protection) su macOS matchano ANCHE gli
            // elementi del portachiavi nuovo — la pulizia della voce vecchia
            // in store() cancellava così l'elemento appena scritto. Con un
            // nome diverso non può più succedere, per costruzione.
            kSecAttrService as String: service + ".dp",
            kSecAttrAccount as String: account,
        ]
        for (k, v) in extra { q[k] = v }
        return q
    }

    /// La voce com'era salvata prima (portachiavi "login", ACL sulla firma):
    /// serve solo per migrare chi arriva da una versione vecchia.
    private static func legacyQuery(_ extra: [String: Any] = [:]) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        for (k, v) in extra { q[k] = v }
        return q
    }
    #else
    private static func query(_ extra: [String: Any] = [:]) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        for (k, v) in extra { q[k] = v }
        return q
    }
    #endif

    static var hasStoredPassword: Bool {
        // Si chiedono gli ATTRIBUTI, non i dati: leggerli non decifra
        // niente (quindi su iOS non fa scattare Face ID), ma la query resta
        // una richiesta valida. Con `kSecReturnData: false` e nient'altro,
        // il portachiavi Data Protection del Mac rispondeva "non trovato"
        // anche a voce presente — scritta OK e mai più vista: era QUESTO a
        // tenere spento il Touch ID.
        var extra: [String: Any] = [kSecReturnAttributes as String: true]
        #if os(iOS)
        // In più, mai mostrare il prompt biometrico solo per un controllo
        // di esistenza.
        extra[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        #endif
        var out: AnyObject?
        let status = SecItemCopyMatching(query(extra) as CFDictionary, &out)
        if status == errSecSuccess || status == errSecInteractionNotAllowed { return true }
        #if os(macOS)
        // Voce vecchia mai migrata: conta comunque come "c'è".
        var legacyOut: AnyObject?
        let legacy = SecItemCopyMatching(legacyQuery([
            kSecReturnAttributes as String: true,
        ]) as CFDictionary, &legacyOut)
        return legacy == errSecSuccess || legacy == errSecInteractionNotAllowed
        #else
        return false
        #endif
    }

    static func store(password: String) throws {
        guard let data = password.data(using: .utf8) else { throw KeychainError.encodingFailed }
        // Solo la voce nuova: quella vecchia (macOS) si tocca DOPO che la
        // scrittura è andata a buon fine — cancellarle entrambe prima di
        // scrivere significava restare senza niente se l'add falliva, ed è
        // esattamente ciò che ha fatto sparire il Touch ID a una migrazione.
        SecItemDelete(query() as CFDictionary)

        var attributes = query([kSecValueData as String: data])

        #if os(iOS)
        // Su iOS l'elemento si protegge da sé: il sistema chiede la biometria
        // a ogni lettura, senza passare da LocalAuthentication.
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil
        ) else {
            throw KeychainError.unhandled(errSecParam)
        }
        attributes[kSecAttrAccessControl as String] = access
        #else
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #endif

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }

        #if os(macOS)
        // Scrittura riuscita: ora sì che la copia vecchia può sparire.
        SecItemDelete(legacyQuery() as CFDictionary)
        #endif
    }

    /// Su iOS la lettura fa scattare da sola Face ID/Touch ID. Su macOS va
    /// chiamata SOLO dopo che LAContext ha già autenticato l'utente.
    static func retrieve(prompt: String) throws -> String {
        var extra: [String: Any] = [kSecReturnData as String: true]
        #if os(iOS)
        extra[kSecUseOperationPrompt as String] = prompt
        #endif
        var result: AnyObject?
        let status = SecItemCopyMatching(query(extra) as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let password = String(data: data, encoding: .utf8) {
            return password
        }

        #if os(macOS)
        if status == errSecItemNotFound {
            // Voce vecchia nel portachiavi "login": la si legge un'ultima
            // volta (può comparire il pannello di sistema, è l'ultima) e la
            // si risistema nel posto nuovo, dove la firma non conta più.
            var legacyResult: AnyObject?
            let legacyStatus = SecItemCopyMatching(
                legacyQuery([kSecReturnData as String: true]) as CFDictionary, &legacyResult)
            if legacyStatus == errSecSuccess, let data = legacyResult as? Data,
               let password = String(data: data, encoding: .utf8) {
                // store() cancella la voce vecchia da sé, ma SOLO a
                // scrittura riuscita: se fallisce, quella resta al suo
                // posto e si riproverà — mai più "cancella e poi si vedrà".
                try? store(password: password)
                return password
            }
        }
        #endif

        if status == errSecItemNotFound { throw KeychainError.notFound }
        throw KeychainError.unhandled(status)
    }

    static func delete() {
        SecItemDelete(query() as CFDictionary)
        #if os(macOS)
        SecItemDelete(legacyQuery() as CFDictionary)
        #endif
    }
}
