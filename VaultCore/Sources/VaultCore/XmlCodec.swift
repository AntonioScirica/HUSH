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
        let doc: XMLDocument
        do {
            doc = try XMLDocument(data: xmlData, options: [])
        } catch {
            throw Kdbx4Error.xmlError("XML non leggibile: \(error.localizedDescription)")
        }
        guard let root = doc.rootElement() else { throw Kdbx4Error.xmlError("elemento radice mancante") }

        // Un'unica passata sull'intero documento per decrittare, nell'ordine
        // corretto, tutti i valori Protected="True" — inclusi quelli dentro
        // rami che poi non useremo (es. History) — cosi' il flusso ChaCha20
        // resta sincronizzato con come e' stato scritto il file.
        var protectedValues: [ObjectIdentifier: String] = [:]
        collectProtectedValues(root, stream: protectStream, into: &protectedValues)

        var databaseName = "Vault"
        var recycleBinUUID: UUID?
        if let meta = root.elements(forName: "Meta").first {
            databaseName = meta.elements(forName: "DatabaseName").first?.stringValue ?? "Vault"
            if let rb = meta.elements(forName: "RecycleBinUUID").first?.stringValue {
                let u = parseUUID(rb)
                if u.uuidString != "00000000-0000-0000-0000-000000000000" { recycleBinUUID = u }
            }
        }

        guard let rootContainer = root.elements(forName: "Root").first,
              let rootGroupEl = rootContainer.elements(forName: "Group").first
        else {
            throw Kdbx4Error.xmlError("gruppo radice mancante")
        }

        let rootGroup = parseGroup(rootGroupEl, protectedValues: protectedValues, recycleBinUUID: recycleBinUUID)
        return VaultDatabase(name: databaseName, root: rootGroup)
    }

    private static func collectProtectedValues(
        _ node: XMLNode, stream: ChaCha20ProtectStream, into map: inout [ObjectIdentifier: String]
    ) {
        if let element = node as? XMLElement,
           element.name == "Value",
           element.attribute(forName: "Protected")?.stringValue == "True" {
            let b64 = element.stringValue ?? ""
            if let ciphertext = Data(base64Encoded: b64) {
                let plain = stream.apply(to: Array(ciphertext))
                map[ObjectIdentifier(element)] = String(bytes: plain, encoding: .utf8) ?? ""
            }
        }
        for child in node.children ?? [] {
            collectProtectedValues(child, stream: stream, into: &map)
        }
    }

    private static func parseGroup(
        _ el: XMLElement, protectedValues: [ObjectIdentifier: String], recycleBinUUID: UUID?
    ) -> VaultGroup {
        let uuid = parseUUID(el.elements(forName: "UUID").first?.stringValue)
        let name = el.elements(forName: "Name").first?.stringValue ?? "Gruppo"
        let group = VaultGroup(id: uuid, name: name)
        if let rb = recycleBinUUID, rb == uuid { group.isRecycleBin = true }

        for entryEl in el.elements(forName: "Entry") {
            group.entries.append(parseEntry(entryEl, protectedValues: protectedValues))
        }
        for subEl in el.elements(forName: "Group") {
            group.subgroups.append(parseGroup(subEl, protectedValues: protectedValues, recycleBinUUID: recycleBinUUID))
        }
        return group
    }

    private static func parseEntry(_ el: XMLElement, protectedValues: [ObjectIdentifier: String]) -> VaultEntry {
        let uuid = parseUUID(el.elements(forName: "UUID").first?.stringValue)
        let iconId = Int(el.elements(forName: "IconID").first?.stringValue ?? "0") ?? 0

        var created = Date()
        var modified = Date()
        if let times = el.elements(forName: "Times").first {
            created = parseKdbxDate(times.elements(forName: "CreationTime").first?.stringValue)
            modified = parseKdbxDate(times.elements(forName: "LastModificationTime").first?.stringValue)
        }

        func field(_ key: String) -> String {
            for stringEl in el.elements(forName: "String") {
                guard stringEl.elements(forName: "Key").first?.stringValue == key,
                      let valueEl = stringEl.elements(forName: "Value").first
                else { continue }
                if valueEl.attribute(forName: "Protected")?.stringValue == "True" {
                    return protectedValues[ObjectIdentifier(valueEl)] ?? ""
                }
                return valueEl.stringValue ?? ""
            }
            return ""
        }

        return VaultEntry(
            id: uuid, title: field("Title"), username: field("UserName"),
            password: field("Password"), url: field("URL"), notes: field("Notes"),
            iconId: iconId, created: created, modified: modified
        )
    }

    // MARK: - Serializzazione

    static func serialize(database: VaultDatabase, protectStream: ChaCha20ProtectStream) throws -> Data {
        let root = XMLElement(name: "KeePassFile")

        let meta = XMLElement(name: "Meta")
        meta.addChild(XMLElement(name: "Generator", stringValue: "Scrigno"))
        meta.addChild(XMLElement(name: "DatabaseName", stringValue: database.name))
        let recycleBin = findRecycleBin(database.root)
        meta.addChild(XMLElement(
            name: "RecycleBinUUID",
            stringValue: uuidToBase64(recycleBin?.id ?? UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)))
        ))
        root.addChild(meta)

        let rootContainer = XMLElement(name: "Root")
        rootContainer.addChild(buildGroupElement(database.root, stream: protectStream))
        root.addChild(rootContainer)

        let doc = XMLDocument(rootElement: root)
        doc.version = "1.0"
        doc.characterEncoding = "utf-8"
        var data = doc.xmlData(options: [.nodeCompactEmptyElement])

        // XMLDocument non permette di impostare "standalone=yes"; sostituiamo
        // qualunque dichiarazione XML generata con quella attesa da KeePass,
        // indipendentemente da come Foundation l'abbia formattata.
        if let text = String(data: data, encoding: .utf8), let range = text.range(of: "?>") {
            let rest = text[range.upperBound...]
            let fixed = "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\"?>" + rest
            data = Data(fixed.utf8)
        }
        return data
    }

    private static func findRecycleBin(_ group: VaultGroup) -> VaultGroup? {
        if group.isRecycleBin { return group }
        for g in group.subgroups {
            if let found = findRecycleBin(g) { return found }
        }
        return nil
    }

    private static func buildGroupElement(_ group: VaultGroup, stream: ChaCha20ProtectStream) -> XMLElement {
        let el = XMLElement(name: "Group")
        el.addChild(XMLElement(name: "UUID", stringValue: uuidToBase64(group.id)))
        el.addChild(XMLElement(name: "Name", stringValue: group.name))
        el.addChild(XMLElement(name: "IconID", stringValue: group.isRecycleBin ? "43" : "48"))
        let times = XMLElement(name: "Times")
        times.addChild(XMLElement(name: "CreationTime", stringValue: formatKdbxDate(Date())))
        times.addChild(XMLElement(name: "LastModificationTime", stringValue: formatKdbxDate(Date())))
        el.addChild(times)
        el.addChild(XMLElement(name: "IsExpanded", stringValue: "True"))

        for entry in group.entries {
            el.addChild(buildEntryElement(entry, stream: stream))
        }
        for sub in group.subgroups {
            el.addChild(buildGroupElement(sub, stream: stream))
        }
        return el
    }

    private static func buildEntryElement(_ entry: VaultEntry, stream: ChaCha20ProtectStream) -> XMLElement {
        let el = XMLElement(name: "Entry")
        el.addChild(XMLElement(name: "UUID", stringValue: uuidToBase64(entry.id)))
        el.addChild(XMLElement(name: "IconID", stringValue: String(entry.iconId)))
        let times = XMLElement(name: "Times")
        times.addChild(XMLElement(name: "CreationTime", stringValue: formatKdbxDate(entry.created)))
        times.addChild(XMLElement(name: "LastModificationTime", stringValue: formatKdbxDate(entry.modified)))
        el.addChild(times)

        func stringField(_ key: String, _ value: String, protected: Bool = false) -> XMLElement {
            let s = XMLElement(name: "String")
            s.addChild(XMLElement(name: "Key", stringValue: key))
            let v = XMLElement(name: "Value")
            if protected {
                let ciphertext = stream.apply(to: Array(value.utf8))
                v.stringValue = Data(ciphertext).base64EncodedString()
                let attr = XMLNode.attribute(withName: "Protected", stringValue: "True") as! XMLNode
                v.addAttribute(attr)
            } else {
                v.stringValue = value
            }
            s.addChild(v)
            return s
        }

        el.addChild(stringField("Title", entry.title))
        el.addChild(stringField("UserName", entry.username))
        el.addChild(stringField("Password", entry.password, protected: true))
        el.addChild(stringField("URL", entry.url))
        el.addChild(stringField("Notes", entry.notes))
        return el
    }
}
