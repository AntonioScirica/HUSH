import Foundation

/// Una voce combacia col sito aperto se l'URL salvato punta lì — ma tante
/// voci (importate, o scritte a mano) non hanno un URL per niente. In quel
/// caso si prova col titolo: se il sito è "netflix.com" e la voce si
/// chiama "Netflix", è comunque un match ragionevole. Stessa logica usata
/// da 1Password e simili.
enum HostMatch {
    static func matches(entryURL: String, entryTitle: String, host: String) -> Bool {
        let host = host.lowercased()
        guard !host.isEmpty else { return true }

        if let entryHost = URL(string: entryURL)?.host?.lowercased(), !entryHost.isEmpty {
            if entryHost.contains(host) || host.contains(entryHost) { return true }
        }

        let sito = siteName(fromHost: host)
        guard !sito.isEmpty else { return false }
        return entryTitle.lowercased().contains(sito)
    }

    /// "accounts.google.com" -> "google", "www.netflix.com" -> "netflix":
    /// il penultimo pezzo (il dominio vero e proprio, non il sottodominio
    /// né il TLD) è quasi sempre il nome che finisce nel titolo della voce.
    private static func siteName(fromHost host: String) -> String {
        var h = host
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
        let parts = h.components(separatedBy: ".")
        guard parts.count >= 2 else { return h }
        return parts[parts.count - 2]
    }
}
