import Foundation
import CryptoKit
import CCommonCrypto

/// SHA-256 via CryptoKit nativo (nessuna dipendenza esterna).
enum HashSHA256 {
    static func hash(_ data: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: Data(data)))
    }
    static func hash(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }
}

/// SHA-512 via CryptoKit nativo.
enum HashSHA512 {
    static func hash(_ data: [UInt8]) -> [UInt8] {
        Array(SHA512.hash(data: Data(data)))
    }
    static func hash(_ data: Data) -> [UInt8] {
        Array(SHA512.hash(data: data))
    }
}

/// HMAC-SHA256 via CryptoKit nativo.
enum HMACSHA256 {
    static func authenticate(key: [UInt8], data: [UInt8]) -> [UInt8] {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(data), using: SymmetricKey(data: key))
        return Array(mac)
    }
}

enum AESError: Error {
    case cryptoFailed(Int32)
    case invalidKeyOrIVSize
}

/// AES-256-CBC, l'unica primitiva per cui serve CommonCrypto (CryptoKit non
/// espone la modalita' CBC, solo GCM). Il padding PKCS7 e' gestito
/// direttamente da CommonCrypto passando l'opzione dedicata.
enum AESCBC {
    static func decrypt(data: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        guard key.count == kCCKeySizeAES256, iv.count == kCCBlockSizeAES128 else {
            throw AESError.invalidKeyOrIVSize
        }
        var outBuffer = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        var outMoved = 0
        let status = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionPKCS7Padding),
            key, key.count,
            iv,
            data, data.count,
            &outBuffer, outBuffer.count,
            &outMoved
        )
        guard status == kCCSuccess else { throw AESError.cryptoFailed(status) }
        return Array(outBuffer.prefix(outMoved))
    }

    static func encrypt(data: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        guard key.count == kCCKeySizeAES256, iv.count == kCCBlockSizeAES128 else {
            throw AESError.invalidKeyOrIVSize
        }
        var outBuffer = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128 * 2)
        var outMoved = 0
        let status = CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionPKCS7Padding),
            key, key.count,
            iv,
            data, data.count,
            &outBuffer, outBuffer.count,
            &outMoved
        )
        guard status == kCCSuccess else { throw AESError.cryptoFailed(status) }
        return Array(outBuffer.prefix(outMoved))
    }
}
