import Foundation

/// Il programma si chiamava Scrigno. Cambiargli nome non è solo una
/// questione di scritte: il bundle identifier è la chiave con cui macOS
/// separa le preferenze di un'app da quelle di un'altra, quindi il giorno in
/// cui cambia, l'app si ritrova davanti a un foglio bianco. Niente
/// verificatore della master password, niente elenco dei progetti: come al
/// primo avvio, con i vault ancora sul disco ma orfani.
///
/// Questo passaggio si occupa di traghettare tutto una volta sola, prima che
/// qualunque altra cosa legga o scriva.
enum Migration {
    private static let fatto = "hush.migrato.da.scrigno"
    private static let vecchioDominio = "com.antonioscirica.scrigno"
    private static let vecchiaCartella = "Scrigno"
    private static let nuovaCartella = "Hush"

    static func run() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: fatto) else { return }

        migraPreferenze()
        migraCartella()
        correggiPercorsiProgetti()

        d.set(true, forKey: fatto)
    }

    /// Le preferenze del vecchio identificativo restano leggibili: si copiano
    /// nel nuovo dominio senza toccare le vecchie, così se qualcosa va storto
    /// la versione precedente funziona ancora.
    private static func migraPreferenze() {
        guard let vecchie = UserDefaults(suiteName: vecchioDominio) else { return }
        let daPortare = vecchie.dictionaryRepresentation().filter { chiave, _ in
            chiave.hasPrefix("scrigno.") || chiave == "vaultProjects" || chiave == "vaultFilePath"
        }
        for (chiave, valore) in daPortare where UserDefaults.standard.object(forKey: chiave) == nil {
            UserDefaults.standard.set(valore, forKey: chiave)
        }
    }

    /// I vault stanno in una cartella che porta il nome dell'app.
    private static func migraCartella() {
        let fm = FileManager.default
        let supporto = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let vecchia = supporto.appendingPathComponent(vecchiaCartella, isDirectory: true)
        let nuova = supporto.appendingPathComponent(nuovaCartella, isDirectory: true)

        guard fm.fileExists(atPath: vecchia.path) else { return }

        if !fm.fileExists(atPath: nuova.path) {
            try? fm.moveItem(at: vecchia, to: nuova)
            return
        }
        // La nuova esiste già (primo avvio arrivato prima della migrazione):
        // si spostano i file uno per uno, senza sovrascrivere niente.
        let dentro = (try? fm.contentsOfDirectory(at: vecchia, includingPropertiesForKeys: nil)) ?? []
        for file in dentro {
            let destinazione = nuova.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath: destinazione.path) {
                try? fm.moveItem(at: file, to: destinazione)
            }
        }
    }

    /// Ogni progetto salvato porta con sé il percorso del suo file, che ora
    /// punta a una cartella che non esiste più.
    private static func correggiPercorsiProgetti() {
        let d = UserDefaults.standard
        guard let data = d.data(forKey: "vaultProjects"),
              let progetti = try? JSONDecoder().decode([VaultFileManager.Project].self, from: data)
        else { return }

        let vecchioPezzo = "/Application Support/\(vecchiaCartella)/"
        let nuovoPezzo = "/Application Support/\(nuovaCartella)/"

        let corretti = progetti.map { p in
            VaultFileManager.Project(
                name: p.name,
                path: p.path.replacingOccurrences(of: vecchioPezzo, with: nuovoPezzo),
                icon: p.icon,
                noteColor: p.noteColor
            )
        }
        if let nuovi = try? JSONEncoder().encode(corretti) {
            d.set(nuovi, forKey: "vaultProjects")
        }

        // anche il file "corrente" ricordato a parte
        if let corrente = d.string(forKey: "vaultFilePath") {
            d.set(corrente.replacingOccurrences(of: vecchioPezzo, with: nuovoPezzo), forKey: "vaultFilePath")
        }
    }
}
