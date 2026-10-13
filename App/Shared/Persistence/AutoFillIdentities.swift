#if os(iOS)
import AuthenticationServices
import Foundation
import VaultCore

/// Registra le voci presso iOS (`ASCredentialIdentityStore`): è quello che
/// fa comparire il suggerimento sopra la tastiera in Safari/Chrome DA SOLO,
/// come 1Password — senza, l'AutoFill c'è ma va aperto a mano ogni volta
/// dal selettore delle password.
///
/// Rilegge i vault da disco invece di appoggiarsi a uno store in memoria
/// specifico (VaultLibrary o VaultStore, usati in punti diversi dell'app):
/// così funziona da qualunque punto lo si chiami, dopo sblocco o modifica.
enum AutoFillIdentities {
    static func sync() {
        guard let password = MasterKey.session else { return }
        let store = ASCredentialIdentityStore.shared
        store.getState { state in
            // l'utente non ha attivato Hush in Impostazioni: niente da fare,
            // e comunque iOS rifiuterebbe la scrittura
            guard state.isEnabled else { return }
            let projects = VaultFileManager.shared.projects
            Task.detached(priority: .utility) {
                var identities: [ASPasswordCredentialIdentity] = []
                for project in projects {
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: project.path)),
                          let db = try? Kdbx4.open(data: Array(data), password: password)
                    else { continue }
                    for entry in db.allEntries {
                        guard !entry.username.isEmpty,
                              let host = host(from: entry.url.isEmpty ? entry.title : entry.url)
                        else { continue }
                        identities.append(ASPasswordCredentialIdentity(
                            serviceIdentifier: ASCredentialServiceIdentifier(identifier: host, type: .domain),
                            user: entry.username,
                            recordIdentifier: entry.id.uuidString
                        ))
                    }
                }
                store.replaceCredentialIdentities(identities, completion: nil)
            }
        }
    }

    /// "https://mail.google.com/x" -> "mail.google.com". Senza uno schema
    /// valido, se il testo somiglia comunque a un dominio (contiene un
    /// punto, niente spazi) si prova a usarlo così com'è.
    private static func host(from raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        if let host = URL(string: raw)?.host, !host.isEmpty { return host }
        if raw.contains("."), !raw.contains(" ") { return raw }
        return nil
    }
}
#endif
