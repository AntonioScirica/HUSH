import SwiftUI

/// Linguaggio visivo "schedario": carta avorio, inchiostro quasi-nero,
/// tab a cartellina numerati, tipografia monospace, chip d'accento gialla.
/// (Ispirato alle reference: index-card dividers / folder tabs.)
enum Theme {
    // Carta e inchiostro
    static let paper = Color(red: 0.925, green: 0.914, blue: 0.880)   // avorio
    static let paperRaised = Color(red: 0.955, green: 0.947, blue: 0.920)
    static let ink = Color(red: 0.135, green: 0.135, blue: 0.125)     // quasi nero caldo
    static let inkSoft = Color(red: 0.135, green: 0.135, blue: 0.125).opacity(0.55)
    static let line = Color(red: 0.135, green: 0.135, blue: 0.125).opacity(0.75)
    static let yellow = Color(red: 0.96, green: 0.72, blue: 0.08)     // chip accento
    static let danger = Color(red: 0.72, green: 0.25, blue: 0.20)

    // Metallo dei cassetti (home progetti)
    static let metal = Color(red: 0.60, green: 0.62, blue: 0.66)
    static let metalDark = Color(red: 0.42, green: 0.44, blue: 0.48)
    static let metalDeep = Color(red: 0.30, green: 0.31, blue: 0.34)

    // Tipografia: mono per etichette/dati, display nero per i titoli
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default)
    }
}

/// Forma a linguetta di cartellina: trapezio con lati obliqui e spigoli
/// superiori ammorbiditi. Riempie il rect; i lati rientrano verso l'alto.
struct TabShape: Shape {
    var slant: CGFloat = 16
    var radius: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tl = CGPoint(x: rect.minX + slant, y: rect.minY)
        let tr = CGPoint(x: rect.maxX - slant, y: rect.minY)
        let bl = CGPoint(x: rect.minX, y: rect.maxY)
        let br = CGPoint(x: rect.maxX, y: rect.maxY)

        func along(_ from: CGPoint, _ to: CGPoint, _ dist: CGFloat) -> CGPoint {
            let dx = to.x - from.x, dy = to.y - from.y
            let len = max(sqrt(dx * dx + dy * dy), 0.001)
            return CGPoint(x: from.x + dx / len * dist, y: from.y + dy / len * dist)
        }

        p.move(to: bl)
        p.addLine(to: along(tl, bl, radius))
        p.addQuadCurve(to: CGPoint(x: tl.x + radius, y: tl.y), control: tl)
        p.addLine(to: CGPoint(x: tr.x - radius, y: tr.y))
        p.addQuadCurve(to: along(tr, br, radius), control: tr)
        p.addLine(to: br)
        return p
    }
}

/// Etichetta stile divider: "001   logo design".
///
/// Il numero è facoltativo: va messo solo dove conta qualcosa davvero (la
/// posizione di una voce nel cassetto). Sulle schermate che non contano
/// niente restava fisso a "001" e faceva solo rumore.
struct IndexLabel: View {
    var number: Int?
    let text: String
    var inverted = false

    var body: some View {
        HStack(spacing: 14) {
            if let number {
                Text(String(format: "%03d", number))
                    .fixedSize()
            }
            Text(text.lowercased())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .font(Theme.mono(13))
        .foregroundStyle(inverted ? Theme.paper : Theme.ink)
    }
}

/// Bottone blocco-inchiostro: rettangolo nero, testo mono maiuscolo chiaro.
/// `prominent` = riempito giallo con testo nero.
struct InkButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(12, .semibold))
            .textCase(.uppercase)
            .tracking(1.2)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .foregroundStyle(prominent ? Theme.ink : Theme.paper)
            .background(prominent ? Theme.yellow : Theme.ink)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// Bottone contorno: solo bordo inchiostro su carta.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(12, .semibold))
            .textCase(.uppercase)
            .tracking(1.2)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .foregroundStyle(Theme.ink)
            .background(Theme.paperRaised)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Campo testo su carta: bordo fine, mono.
struct PaperFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(Theme.mono(13))
            .padding(10)
            .background(Theme.paperRaised)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
    }
}

extension View {
    func paperBackground() -> some View {
        background(Theme.paper.ignoresSafeArea())
    }
}

extension Color {
    /// Colore da stringa esadecimale "#RRGGBB" (grigio se non valida).
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = Int(s, radix: 16) else {
            self = .gray
            return
        }
        self = Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
