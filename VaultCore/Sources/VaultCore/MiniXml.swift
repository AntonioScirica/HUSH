import Foundation

/// Albero XML minimo, portabile ovunque.
///
/// Su macOS Foundation offre XMLDocument, su iOS no: lì esiste solo il
/// parser a eventi. Questo è il pezzetto di DOM che serve al formato KDBX
/// (elementi, attributi, testo), identico sulle due piattaforme, così il
/// codec resta uno solo.
final class XmlEl {
    let name: String
    var attributes: [String: String] = [:]
    var text: String = ""
    var children: [XmlEl] = []

    init(name: String) {
        self.name = name
    }

    convenience init(name: String, text: String) {
        self.init(name: name)
        self.text = text
    }

    func addChild(_ child: XmlEl) {
        children.append(child)
    }

    func elements(_ name: String) -> [XmlEl] {
        children.filter { $0.name == name }
    }

    func first(_ name: String) -> XmlEl? {
        children.first { $0.name == name }
    }

    // MARK: - Lettura

    /// Costruisce l'albero da bytes. Errore se l'XML non sta in piedi.
    static func parse(_ data: Data) throws -> XmlEl {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            let motivo = parser.parserError?.localizedDescription ?? "documento vuoto"
            throw Kdbx4Error.xmlError("XML non leggibile: \(motivo)")
        }
        return root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XmlEl?
        private var stack: [XmlEl] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            let el = XmlEl(name: name)
            el.attributes = attributes
            if let parent = stack.last {
                parent.addChild(el)
            } else {
                root = el
            }
            stack.append(el)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            // solo sulle foglie: il testo "di cornice" fra i figli (a capo,
            // rientri) non è un valore e sporcherebbe la lettura
            guard let corrente = stack.last, corrente.children.isEmpty else { return }
            corrente.text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard let corrente = stack.last,
                  let testo = String(data: CDATABlock, encoding: .utf8) else { return }
            corrente.text += testo
        }
    }

    // MARK: - Scrittura

    /// Il documento intero, con la dichiarazione che si aspetta KeePass.
    func documentData() -> Data {
        var out = "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\"?>"
        write(into: &out)
        return Data(out.utf8)
    }

    private func write(into out: inout String) {
        out += "<\(name)"
        for (chiave, valore) in attributes.sorted(by: { $0.key < $1.key }) {
            out += " \(chiave)=\"\(Self.escape(valore, attribute: true))\""
        }
        if children.isEmpty && text.isEmpty {
            out += "/>"
            return
        }
        out += ">"
        if !text.isEmpty {
            out += Self.escape(text, attribute: false)
        }
        for figlio in children {
            figlio.write(into: &out)
        }
        out += "</\(name)>"
    }

    private static func escape(_ s: String, attribute: Bool) -> String {
        var r = s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        if attribute {
            r = r.replacingOccurrences(of: "\"", with: "&quot;")
        }
        return r
    }
}
