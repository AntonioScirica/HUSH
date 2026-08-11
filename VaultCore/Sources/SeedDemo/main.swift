import Foundation
import VaultCore
import Security

// Script una tantum per popolare Hush con progetti finti, per demo e video.
// Non fa parte dell'app: rigenera la master password (stampata sotto),
// disattiva tour e onboarding, attiva la licenza di prova del test-suite e
// scrive vault ed elenco progetti come farebbe l'app stessa.

let demoPassword = "Demo1234!"
let defaults = UserDefaults(suiteName: "com.antonioscirica.hush")!

func randomBytes(_ n: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: n)
    _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
    return bytes
}

// 1) master password del demo (sovrascrive quella configurata)
let salt = randomBytes(32)
let verifier = try Argon2.derive(password: demoPassword, salt: salt)
defaults.set(Data(salt), forKey: "scrigno.master.salt")
defaults.set(Data(verifier), forKey: "scrigno.master.verifier")
defaults.set(Date().timeIntervalSince1970, forKey: "scrigno.master.lastTyped")
defaults.removeObject(forKey: "scrigno.master.biometry")

// niente tour sulla parete, niente migrazione che riparte
defaults.set(true, forKey: "scrigno.pref.vistoAiutoParete")
defaults.set(true, forKey: "hush.migrato.da.scrigno")

// 2) licenza (quella firmata davvero, dal test-suite) legata a questa macchina
let licenza = "eyJlbWFpbCI6ImNsaWVudGVAZXNlbXBpby5pdCIsInBsYW4iOiJ2aXRhIiwiaXNzdWVkIjoxNzg2MjQwODYxfQ.fLy9wniDy52LXsrW4GULwTYpWDTzuZHfO0oqJ7XhIlI0wMFm7IbXDs55cy8nijE7zGMmYX9G38n2yK3MmSzzBA"
defaults.set(licenza, forKey: "scrigno.license")
import IOKit
let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
if entry != 0,
   let cf = IORegistryEntryCreateCFProperty(entry, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0),
   let uuid = cf.takeRetainedValue() as? String {
    defaults.set(uuid, forKey: "scrigno.license.device")
}
IOObjectRelease(entry)

// 3) cartella dei cassetti, ripulita
let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Hush", isDirectory: true)
try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
for f in (try? FileManager.default.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil)) ?? [] {
    if f.pathExtension == "kdbx" { try? FileManager.default.removeItem(at: f) }
}

struct Progetto {
    let nome: String
    let icona: String
    let colore: String
    let voci: [(titolo: String, utente: String, password: String, url: String)]
}

let coloriPostIt = ["#FADA5C", "#F4A9A8", "#A8D8B9", "#9EC5E8", "#D9B8E8", "#F0C9A0"]

func vociFinte(_ n: Int, dominio: String) -> [(titolo: String, utente: String, password: String, url: String)] {
    (1...n).map { i in
        (titolo: "\(dominio) · account \(i)",
         utente: "utente\(i)@\(dominio.lowercased().replacingOccurrences(of: " ", with: "")).com",
         password: PasswordGenerator.generate(.init(length: 16)),
         url: "https://\(dominio.lowercased().replacingOccurrences(of: " ", with: "")).com")
    }
}

let progetti: [Progetto] = [
    Progetto(nome: "Netflix", icona: "tv", colore: coloriPostIt[0], voci: vociFinte(5, dominio: "Netflix")),
    Progetto(nome: "Banca", icona: "banknote", colore: coloriPostIt[1], voci: vociFinte(6, dominio: "Banca")),
    // il progetto "vetrina" per gli screenshot: tante voci, nomi veri
    Progetto(nome: "Lavoro", icona: "briefcase", colore: coloriPostIt[2], voci: [
        "GitLab", "AWS Console", "VPN aziendale", "Slack", "Jira", "Figma",
        "Notion", "Google Workspace", "WordPress admin", "Server FTP",
        "Database produzione", "Grafana", "Sentry", "Mailchimp",
    ].map { nome in
        (titolo: nome,
         utente: "antonio@studio.it",
         password: PasswordGenerator.generate(.init(length: 16)),
         url: "https://\(nome.lowercased().replacingOccurrences(of: " ", with: "")).com")
    }),
    Progetto(nome: "Email personale", icona: "envelope", colore: coloriPostIt[3], voci: vociFinte(5, dominio: "Mail")),
    Progetto(nome: "Social", icona: "person.2", colore: coloriPostIt[4], voci: vociFinte(6, dominio: "Social")),
    Progetto(nome: "Gaming", icona: "gamecontroller", colore: coloriPostIt[5], voci: vociFinte(5, dominio: "Gaming")),
    Progetto(nome: "Cloud", icona: "cloud", colore: coloriPostIt[0], voci: vociFinte(6, dominio: "Cloud")),
    Progetto(nome: "Famiglia", icona: "house", colore: coloriPostIt[1], voci: vociFinte(5, dominio: "Famiglia")),
    Progetto(nome: "Shopping", icona: "cart", colore: coloriPostIt[2], voci: vociFinte(6, dominio: "Shopping")),
    Progetto(nome: "Server", icona: "server.rack", colore: coloriPostIt[3], voci: vociFinte(5, dominio: "Server")),
]

struct ProjectRecord: Codable {
    let name: String
    let path: String
    var icon: String?
    var noteColor: String?
}

var elenco: [ProjectRecord] = []

func percorsoLibero(nome: String) -> URL {
    let base = nome.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
    var url = supportDir.appendingPathComponent("\(base).kdbx")
    var n = 2
    while FileManager.default.fileExists(atPath: url.path) {
        url = supportDir.appendingPathComponent("\(base)-\(n).kdbx")
        n += 1
    }
    return url
}

for p in progetti {
    let db = VaultDatabase.createNew(name: p.nome)
    for v in p.voci {
        db.addEntry(VaultEntry(
            title: v.titolo, username: v.utente, password: v.password, url: v.url,
            customFields: [VaultCustomField(key: "scrigno.kind", value: "login")]
        ))
    }
    let bytes = try Kdbx4.save(database: db, password: demoPassword)
    let url = percorsoLibero(nome: p.nome)
    try Data(bytes).write(to: url, options: .atomic)
    elenco.append(ProjectRecord(name: p.nome, path: url.path, icon: p.icona, noteColor: p.colore))
    print("creato \(p.nome): \(p.voci.count) voci")
}

let data = try JSONEncoder().encode(elenco)
defaults.set(data, forKey: "vaultProjects")
defaults.synchronize()

print("")
print("Fatto. \(progetti.count) progetti, licenza attiva, tour spento.")
print("Master password demo: \(demoPassword)")
