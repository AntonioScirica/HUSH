import Foundation

/// Lettura/scrittura del payload XML interno di un database KDBX4 (la parte
/// che resta dopo aver tolto header, compressione GZip e cifratura).
///
/// Nota su cosa è modellato: per restare un progetto sostenibile, VaultCore
/// legge/scrive Meta (nome database + cestino), l'albero di gruppi ed i campi
/// standard di ogni voce (Titolo, Utente, Password, URL, Note, icona, date).
/// Cronologia delle modifiche, allegati binari e campi personalizzati di
/// vault creati con altri programmi (es. KeePassXC) NON vengono preservati
/// se il vault viene poi risalvato da questa app — vengono letti e ignorati.
enum XmlCodec {

    // MARK: - Date KDBX (formato binario: secondi dal 0001-01-01, LE 8 byte)

    private static let epochOffsetSeconds: Double = 62_135_596_800

    private static func parseKdbxDate(_ text: String?) -> Date {
        guard let text = text, !text.isEmpty else { return Date() }
        if text.contains(":") {
            // Formato testuale ISO8601 (usato da alcune versioni/vault legacy)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: text) { return d }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: text) { return d }
            return Date()
        }
        guard let raw = Data(base64Encoded: text), raw.count == 8 else { return Date() }
        let r = ByteReader(raw)
        guard let secondsFrom0001 = try? r.readUInt64LE() else { return Date() }
        let unixSeconds = Double(secondsFrom0001) - epochOffsetSeconds
        return Date(timeIntervalSince1970: unixSeconds)
    }

    private static func formatKdbxDate(_ date: Date) -> String {
        let secondsFrom0001 = UInt64(date.timeIntervalSince1970 + epochOffsetSeconds)
        let w = ByteWriter()
        w.writeUInt64LE(secondsFrom0001)
        return Data(w.bytes).base64EncodedString()
    }

    // MARK: - UUID <-> base64(16 byte)

    private static func parseUUID(_ text: String?) -> UUID {
        guard let text = text, let data = Data(base64Encoded: text), data.count == 16 else { return UUID() }
        return data.withUnsafeBytes { raw -> UUID in
            NSUUID(uuidBytes: raw.bindMemory(to: UInt8.self).baseAddress!) as UUID
        }
    }

    private static func uuidToBase64(_ uuid: UUID) -> String {
        var u = uuid.uuid
        let data = withUnsafeBytes(of: &u) { Data($0) }
        return data.base64EncodedString()
    }

    // MARK: - Parsing

    static func parse(xmlData: Data, protectStream: ChaCha20ProtectStream) throws -> VaultDatabase {
        let root = try XmlEl.parse(xmlData)

        // Un'unica passata sull'intero documento per decrittare, nell'ordine
        // corretto, tutti i valori Protected="True" — inclusi quelli dentro
        // rami che poi non useremo (es. History) — cosi' il flusso ChaCha20
        // resta sincronizzato con come e' stato scritto il file.
        var protectedValues: [ObjectIdentifier: String] = [:]
        collectProtectedValues(root, stream: protectStream, into: &protectedValues)

        var databaseName = "Vault"
        var recycleBinUUID: UUID?
        if let meta = root.first("Meta") {
            databaseName = meta.first("DatabaseName").map(\.text) ?? "Vault"
            if let rb = meta.first("RecycleBinUUID")?.text {
                let u = parseUUID(rb)
                if u.uuidString != "00000000-0000-0000-0000-000000000000" { recycleBinUUID = u }
            }
        }

        guard let rootContainer = root.first("Root"),
              let rootGroupEl = rootContainer.first("Group")
        else {
            throw Kdbx4Error.xmlError("gruppo radice mancante")
        }

        let rootGroup = parseGroup(rootGroupEl, protectedValues: protectedValues, recycleBinUUID: recycleBinUUID)
        return VaultDatabase(name: databaseName, root: rootGroup)
    }

    private static func collectProtectedValues(
        _ node: XmlEl, stream: ChaCha20ProtectStream, into map: inout [ObjectIdentifier: String]
    ) {
        if node.name == "Value", node.attributes["Protected"] == "True" {
            if let ciphertext = Data(base64Encoded: node.text) {
                let plain = stream.apply(to: Array(ciphertext))
                map[ObjectIdentifier(node)] = String(bytes: plain, encoding: .utf8) ?? ""
            }
        }
        for child in node.children {
            collectProtectedValues(child, stream: stream, into: &map)
        }
    }

    private static func parseGroup(
        _ el: XmlEl, protectedValues: [ObjectIdentifier: String], recycleBinUUID: UUID?
    ) -> VaultGroup {
        let uuid = parseUUID(el.first("UUID")?.text)
        let name = el.first("Name").map(\.text) ?? "Gruppo"
        let group = VaultGroup(id: uuid, name: name)
        if let rb = recycleBinUUID, rb == uuid { group.isRecycleBin = true }

        for entryEl in el.elements("Entry") {
            group.entries.append(parseEntry(entryEl, protectedValues: protectedValues))
        }
        for subEl in el.elements("Group") {
            group.subgroups.append(parseGroup(subEl, protectedValues: protectedValues, recycleBinUUID: recycleBinUUID))
        }
        return group
    }

    private static func parseEntry(_ el: XmlEl, protectedValues: [ObjectIdentifier: String]) -> VaultEntry {
        let uuid = parseUUID(el.first("UUID")?.text)
        let iconId = Int(el.first("IconID")?.text ?? "0") ?? 0

        var created = Date()
        var modified = Date()
        if let times = el.first("Times") {
            created = parseKdbxDate(times.first("CreationTime")?.text)
            modified = parseKdbxDate(times.first("LastModificationTime")?.text)
        }

        func field(_ key: String) -> String {
            for stringEl in el.elements("String") {
                guard stringEl.first("Key")?.text == key,
                      let valueEl = stringEl.first("Value")
                else { continue }
                if valueEl.attributes["Protected"] == "True" {
                    return protectedValues[ObjectIdentifier(valueEl)] ?? ""
                }
                return valueEl.text
            }
            return ""
        }

        // Tutto ciò che non è uno dei cinque canonici è un campo libero, e va
        // conservato: buttarlo via al primo salvataggio vorrebbe dire perdere
        // i dati messi da un altro programma, oltre ai nostri.
        let standard: Set<String> = ["Title", "UserName", "Password", "URL", "Notes"]
        var extras: [VaultCustomField] = []
        for stringEl in el.elements("String") {
            guard let key = stringEl.first("Key")?.text,
                  !standard.contains(key),
                  let valueEl = stringEl.first("Value")
            else { continue }
            let isProtected = valueEl.attributes["Protected"] == "True"
            let value = isProtected
                ? (protectedValues[ObjectIdentifier(valueEl)] ?? "")
                : valueEl.text
            extras.append(VaultCustomField(key: key, value: value, isProtected: isProtected))
        }

        return VaultEntry(
            id: uuid, title: field("Title"), username: field("UserName"),
            password: field("Password"), url: field("URL"), notes: field("Notes"),
            iconId: iconId, created: created, modified: modified,
            customFields: extras
        )
    }

    // MARK: - Serializzazione

    static func serialize(database: VaultDatabase, protectStream: ChaCha20ProtectStream) throws -> Data {
        let root = XmlEl(name: "KeePassFile")

        let meta = XmlEl(name: "Meta")
        meta.addChild(XmlEl(name: "Generator", text: "Hush"))
        meta.addChild(XmlEl(name: "DatabaseName", text: database.name))
        let recycleBin = findRecycleBin(database.root)
        meta.addChild(XmlEl(
            name: "RecycleBinUUID",
            text: uuidToBase64(recycleBin?.id ?? UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)))
        ))
        root.addChild(meta)

        let rootContainer = XmlEl(name: "Root")
        rootContainer.addChild(buildGroupElement(database.root, stream: protectStream))
        root.addChild(rootContainer)

        return root.documentData()
    }

    private static func findRecycleBin(_ group: VaultGroup) -> VaultGroup? {
        if group.isRecycleBin { return group }
        for g in group.subgroups {
            if let found = findRecycleBin(g) { return found }
        }
        return nil
    }

    private static func buildGroupElement(_ group: VaultGroup, stream: ChaCha20ProtectStream) -> XmlEl {
        let el = XmlEl(name: "Group")
        el.addChild(XmlEl(name: "UUID", text: uuidToBase64(group.id)))
        el.addChild(XmlEl(name: "Name", text: group.name))
        el.addChild(XmlEl(name: "IconID", text: group.isRecycleBin ? "43" : "48"))
        let times = XmlEl(name: "Times")
        times.addChild(XmlEl(name: "CreationTime", text: formatKdbxDate(Date())))
        times.addChild(XmlEl(name: "LastModificationTime", text: formatKdbxDate(Date())))
        el.addChild(times)
        el.addChild(XmlEl(name: "IsExpanded", text: "True"))

        for entry in group.entries {
            el.addChild(buildEntryElement(entry, stream: stream))
        }
        for sub in group.subgroups {
            el.addChild(buildGroupElement(sub, stream: stream))
        }
        return el
    }

    private static func buildEntryElement(_ entry: VaultEntry, stream: ChaCha20ProtectStream) -> XmlEl {
        let el = XmlEl(name: "Entry")
        el.addChild(XmlEl(name: "UUID", text: uuidToBase64(entry.id)))
        el.addChild(XmlEl(name: "IconID", text: String(entry.iconId)))
        let times = XmlEl(name: "Times")
        times.addChild(XmlEl(name: "CreationTime", text: formatKdbxDate(entry.created)))
        times.addChild(XmlEl(name: "LastModificationTime", text: formatKdbxDate(entry.modified)))
        el.addChild(times)

        func stringField(_ key: String, _ value: String, protected: Bool = false) -> XmlEl {
            let s = XmlEl(name: "String")
            s.addChild(XmlEl(name: "Key", text: key))
            let v = XmlEl(name: "Value")
            if protected {
                let ciphertext = stream.apply(to: Array(value.utf8))
                v.text = Data(ciphertext).base64EncodedString()
                v.attributes["Protected"] = "True"
            } else {
                v.text = value
            }
            s.addChild(v)
            return s
        }

        el.addChild(stringField("Title", entry.title))
        el.addChild(stringField("UserName", entry.username))
        el.addChild(stringField("Password", entry.password, protected: true))
        el.addChild(stringField("URL", entry.url))
        el.addChild(stringField("Notes", entry.notes))
        for extra in entry.customFields {
            el.addChild(stringField(extra.key, extra.value, protected: extra.isProtected))
        }
        return el
    }
}
