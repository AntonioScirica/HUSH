import Foundation
import VaultCore

/// Modalità demo per registrare video e screenshot con dati inventati.
///
/// Si accende solo con HUSH_DEMO=1 e solo nelle build Debug: in Release il
/// flag è sempre falso. Va lanciata da una copia dell'app con bundle id
/// diverso (preferenze, verificatore e lista progetti stanno in
/// `UserDefaults.standard`, che segue il bundle id): così non vede né tocca i
/// cassetti veri.
enum DemoMode {
    #if DEBUG
    static let attivo = ProcessInfo.processInfo.environment["HUSH_DEMO"] == "1"
    #else
    static let attivo = false
    #endif

    static let password = "Demo12345!"

    /// Al primo avvio della copia demo: master password nota, tour saltato,
    /// cassetti pieni di voci d'esempio.
    static func seedIfNeeded() {
        guard attivo, !MasterKey.isConfigured else { return }
        MasterKey.configure(password: password)
        UserDefaults.standard.set(true, forKey: "scrigno.pref.vistoAiutoParete")

        seed("Lavoro", "briefcase", "#A8D8B9", [
            ("GitHub", "mario.rossi", "Xk9#mPz2Qw7v", "github.com"),
            ("Slack", "mario@azienda.com", "Tr4v#Nk82Lm", "azienda.slack.com"),
            ("Google Workspace", "mario@azienda.com", "Aw9$Kp3Vn2Xz", "workspace.google.com"),
        ])
        seed("Banca", "banknote", "#F4A9A8", [
            ("Intesa Sanpaolo", "MRRRSS80A01H501X", "Bk8@Rm3Fn7Qz", "intesasanpaolo.com"),
            ("Revolut", "+39 333 1234567", "Rv5#Tp9Kx2Mn", "revolut.com"),
        ])
        seed("Streaming", "tv", "#FADA5C", [
            ("Netflix", "mario.rossi@email.it", "Nf7!Qw2Mx9Pz", "netflix.com"),
            ("Netflix Famiglia", "famiglia.rossi@email.it", "Nf3#Lp8Vt3Rk", "netflix.com"),
            ("Spotify", "mario.rossi@email.it", "Sp4$Nq6Wb4Ty", "spotify.com"),
            ("Disney+", "famiglia.rossi@email.it", "Ds3#Nk82Lm7q", "disneyplus.com"),
        ])
        seed("Email", "envelope", "#9EC5E8", [
            ("Gmail", "mario.rossi@email.it", "Gm4#Lp8Vt3Rk", "gmail.com"),
            ("Outlook", "mario.rossi@outlook.it", "Ol2#Rm8Fn4Xz", "outlook.com"),
        ])
        seed("Famiglia", "house", "#F4A9A8", [
            ("Wifi di casa", "", "Cs9!Vt4Rk2Mn", ""),
            ("Fascicolo sanitario", "MRRRSS80A01H501X", "Hp7$Nk3Vt9Qz", "fascicolosanitario.it"),
        ])
        seed("Social", "person.2", "#D9B8E8", [
            ("Instagram", "mario.rossi", "In8$Kp3Vn2Xz", "instagram.com"),
            ("LinkedIn", "mario.rossi@email.it", "Lk4#Tp9Mx7Qz", "linkedin.com"),
        ])
        seed("Viaggi", "airplane", "#F0C9A0", [
            ("Booking.com", "mario.rossi@email.it", "Bk4!Qw9Mx2Pz", "booking.com"),
            ("Trenitalia", "mario.rossi@email.it", "Tr2$Nq6Wb9Ty", "trenitalia.com"),
        ])
        seed("Gaming", "gamecontroller", "#F0C9A0", [
            ("Steam", "mariorossi80", "Sm5#Lp8Vt3Rk", "steamcommunity.com"),
            ("PlayStation Network", "mario_rossi", "Ps9@Rm3Fn7Qz", "playstation.com"),
        ])
        seed("Cloud", "cloud", "#FADA5C", [
            ("iCloud", "mario.rossi@email.it", "Ic6!Vt4Rk2Mn", "icloud.com"),
            ("Dropbox", "mario.rossi@email.it", "Db3#Nk82Lm7q", "dropbox.com"),
        ])
    }

    private static func seed(_ project: String, _ icon: String, _ color: String, _ entries: [(String, String, String, String)]) {
        let db = VaultDatabase.createNew(name: project)
        for (title, user, pass, url) in entries {
            db.addEntry(VaultEntry(title: title, username: user, password: pass, url: url))
        }
        guard let bytes = try? Kdbx4.save(database: db, password: password) else { return }
        let url = VaultFileManager.shared.projectsDirectory.appendingPathComponent("\(project).kdbx")
        try? Data(bytes).write(to: url)
        try? VaultFileManager.shared.addProject(name: project, url: url, icon: icon, noteColor: color)
    }
}
