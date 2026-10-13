import SwiftUI
import VaultCore

@main
struct ScrignoiOSApp: App {
    init() {
        #if DEBUG
        DemoSeed.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

#if DEBUG
/// Popola un vault demo con progetti e voci finte, per generare gli
/// screenshot dell'App Store senza toccare dati reali. Si attiva SOLO con
/// la variabile d'ambiente HUSH_SEED_DEMO=1 (mai in una build normale), ed
/// è compilato solo in Debug: in Release il codice proprio non esiste.
enum DemoSeed {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["HUSH_SEED_DEMO"] == "1" else { return }

        let password = "Demo12345!"
        MasterKey.configure(password: password)

        seed(project: "Lavoro", icon: "briefcase", noteColor: "#F5B814", entries: [
            ("GitHub", "mario.rossi", "Xk9#mPz2Qw7v", "github.com"),
            ("Slack Aziendale", "mario@azienda.com", "Tr4v#Nk82Lm", "azienda.slack.com"),
            ("AWS Console", "mario.rossi", "Aw9$Kp3Vn2Xz", "console.aws.amazon.com"),
        ], password: password)

        seed(project: "Personale", icon: "house", noteColor: nil, entries: [
            ("Netflix", "mario.rossi@icloud.com", "Nf7!Qw2Mx9Pz", "netflix.com"),
            ("Gmail", "mario.rossi@gmail.com", "Gm4#Lp8Vt3Rk", "gmail.com"),
            ("Amazon", "mario.rossi@icloud.com", "Az2$Nq6Wb4Ty", "amazon.it"),
        ], password: password)

        seed(project: "Finanza", icon: "creditcard", noteColor: "#F5B814", entries: [
            ("Intesa Sanpaolo", "MRRRSS80A01H501X", "Bk8@Rm3Fn7Qz", "intesasanpaolo.com"),
            ("Revolut", "+39 333 1234567", "Rv5#Tp9Kx2Mn", "revolut.com"),
        ], password: password)

        seed(project: "Famiglia", icon: "person.2", noteColor: nil, entries: [
            ("Disney+", "famiglia.rossi@icloud.com", "Ds3#Nk82Lm7q", "disneyplus.com"),
            ("Wifi di casa", "", "Cs9!Vt4Rk2Mn", ""),
        ], password: password)

        seed(project: "Salute", icon: "cross.case", noteColor: "#F5B814", entries: [
            ("CUP Regionale", "mario.rossi", "Hp7$Nk3Vt9Qz", "cupweb.regione.it"),
            ("App Farmacia", "mario.rossi@gmail.com", "Ph2#Rm8Fn4Xz", "farmaciaonline.it"),
        ], password: password)

        seed(project: "Viaggi", icon: "airplane", noteColor: nil, entries: [
            ("Booking.com", "mario.rossi@gmail.com", "Bk4!Qw9Mx2Pz", "booking.com"),
            ("Ryanair", "mario.rossi@gmail.com", "Ry7#Tp3Kx8Mn", "ryanair.com"),
            ("Trenitalia", "mario.rossi@gmail.com", "Tr2$Nq6Wb9Ty", "trenitalia.com"),
        ], password: password)

        seed(project: "Svago", icon: "gamecontroller", noteColor: nil, entries: [
            ("Steam", "mariorossi80", "Sm5#Lp8Vt3Rk", "steamcommunity.com"),
            ("PlayStation Network", "mario_rossi", "Ps9@Rm3Fn7Qz", "playstation.com"),
            ("Nintendo Account", "mario.rossi@gmail.com", "Nt6#Wq3Rk9Vz", "nintendo.com"),
            ("Twitch", "mariorossi_tv", "Tw2$Pl7Mn4Xk", "twitch.tv"),
            ("Discord", "mario.rossi@gmail.com", "Dc9!Rk3Vt8Qz", "discord.com"),
            ("Epic Games", "mario_rossi", "Ep4#Nk82Lm7q", "epicgames.com"),
            ("Xbox Live", "mario.rossi@outlook.com", "Xb7$Tp3Kx8Mn", "xbox.com"),
        ], password: password)

        seed(project: "Auto", icon: "car", noteColor: "#F5B814", entries: [
            ("Assicurazione", "mario.rossi", "Ac6!Vt4Rk2Mn", "assicurazione.it"),
            ("App Ricarica", "mario.rossi@gmail.com", "Rc3#Nk82Lm7q", "enelx.com"),
        ], password: password)

        seed(project: "Social", icon: "at", noteColor: nil, entries: [
            ("Instagram", "mario.rossi", "In8$Kp3Vn2Xz", "instagram.com"),
            ("LinkedIn", "mario.rossi@gmail.com", "Lk4#Tp9Mx7Qz", "linkedin.com"),
            ("X", "mario_rossi", "Xz2!Nq6Wb4Ty", "x.com"),
        ], password: password)
    }

    private static func seed(project: String, icon: String, noteColor: String?, entries: [(String, String, String, String)], password: String) {
        let db = VaultDatabase.createNew(name: project)
        for (title, user, pass, url) in entries {
            db.addEntry(VaultEntry(title: title, username: user, password: pass, url: url))
        }
        guard let bytes = try? Kdbx4.save(database: db, password: password) else { return }
        let url = VaultFileManager.shared.projectsDirectory.appendingPathComponent("\(project).kdbx")
        try? Data(bytes).write(to: url)
        try? VaultFileManager.shared.addProject(name: project, url: url, icon: icon, noteColor: noteColor)
    }
}
#endif
