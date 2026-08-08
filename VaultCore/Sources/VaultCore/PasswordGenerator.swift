import Foundation
import Security

public struct PasswordGeneratorOptions {
    public var length: Int
    public var lowercase: Bool
    public var uppercase: Bool
    public var digits: Bool
    public var symbols: Bool

    public init(length: Int = 20, lowercase: Bool = true, uppercase: Bool = true, digits: Bool = true, symbols: Bool = true) {
        self.length = length
        self.lowercase = lowercase
        self.uppercase = uppercase
        self.digits = digits
        self.symbols = symbols
    }
}

public enum PasswordGenerator {
    private static let charsets: [(key: WritableKeyPath<PasswordGeneratorOptions, Bool>, chars: String)] = [
        (\.lowercase, "abcdefghijklmnopqrstuvwxyz"),
        (\.uppercase, "ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
        (\.digits, "0123456789"),
        (\.symbols, "!@#$%^&*()-_=+[]{};:,.<>?/~"),
    ]

    /// Genera una password casuale crittograficamente sicura (SecRandomCopyBytes).
    public static func generate(_ options: PasswordGeneratorOptions) -> String {
        var groups: [String] = []
        var pool = ""
        for (key, chars) in charsets where options[keyPath: key] {
            groups.append(chars)
            pool += chars
        }
        guard !pool.isEmpty, options.length > 0 else { return "" }
        let poolChars = Array(pool)

        func randomIndex(_ upperBound: Int) -> Int {
            var v: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &v) { SecRandomCopyBytes(kSecRandomDefault, 4, $0.baseAddress!) }
            return Int(v % UInt32(upperBound))
        }

        var result: [Character] = []
        for g in groups {
            let chars = Array(g)
            result.append(chars[randomIndex(chars.count)])
        }
        while result.count < options.length {
            result.append(poolChars[randomIndex(poolChars.count)])
        }
        // Fisher-Yates con indice casuale crittografico
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            let j = randomIndex(i + 1)
            result.swapAt(i, j)
        }
        return String(result.prefix(options.length))
    }

    public enum Strength: Int {
        case weak = 1, fair = 2, good = 3, excellent = 4

        public var label: String {
            switch self {
            case .weak: return "debole"
            case .fair: return "discreta"
            case .good: return "buona"
            case .excellent: return "eccellente"
            }
        }
    }

    public static func strength(of password: String) -> Strength {
        guard !password.isEmpty else { return .weak }
        var poolSize = 0
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { poolSize += 26 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { poolSize += 26 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { poolSize += 10 }
        let alnum = CharacterSet.alphanumerics
        if password.rangeOfCharacter(from: alnum.inverted) != nil { poolSize += 30 }
        let entropy = Double(password.count) * log2(Double(max(poolSize, 1)))
        if entropy < 40 { return .weak }
        if entropy < 60 { return .fair }
        if entropy < 90 { return .good }
        return .excellent
    }
}
