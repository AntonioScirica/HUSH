import Foundation
import Security

public enum Kdbx4Error: Error, LocalizedError {
    case badSignature
    case unsupportedVersion(major: Int, minor: Int)
    case corruptFile(String)
    case invalidPassword
    case unsupportedCipher
    case unsupportedKdf(String)
    case xmlError(String)

    public var errorDescription: String? {
        switch self {
        case .badSignature: return "Il file non è un vault KeePass (.kdbx) valido."
        case .unsupportedVersion(let maj, let min): return "Versione KDBX non supportata: \(maj).\(min)."
        case .corruptFile(let s): return "File corrotto: \(s)"
        case .invalidPassword: return "Master password errata."
        case .unsupportedCipher: return "Algoritmo di cifratura non supportato."
        case .unsupportedKdf(let s): return "KDF non supportato: \(s). Riapri il vault con KeePassXC e passa ad Argon2."
        case .xmlError(let s): return "Errore nel contenuto XML del vault: \(s)"
        }
    }
}

// Identificatori binari (UUID a 16 byte) usati nell'header KDBX4, decodificati
// dalle stringhe base64 note della specifica KeePass / kdbxweb.
private enum KdbxIds {
    static let cipherAES: [UInt8] = [0x31,0xc1,0xf2,0xe6,0xbf,0x71,0x43,0x50,0xbe,0x58,0x05,0x21,0x6a,0xfc,0x5a,0xff]
    static let cipherChaCha20: [UInt8] = [0xd6,0x03,0x8a,0x2b,0x8b,0x6f,0x4c,0xb5,0xa5,0x24,0x33,0x9a,0x31,0xdb,0xb5,0x9a]
    static let kdfArgon2d: [UInt8] = [0xef,0x63,0x6d,0xdf,0x8c,0x29,0x44,0x4b,0x91,0xf7,0xa9,0xa4,0x03,0xe3,0x0a,0x0c]
    static let kdfArgon2id: [UInt8] = [0x9e,0x29,0x8b,0x19,0x56,0xdb,0x47,0x73,0xb2,0x3d,0xfc,0x3e,0xc6,0xf0,0xa1,0xe6]
}

private let headerFieldNames = [
    "EndOfHeader", "Comment", "CipherID", "CompressionFlags", "MasterSeed",
    "TransformSeed", "TransformRounds", "EncryptionIV", "ProtectedStreamKey",
    "StreamStartBytes", "InnerRandomStreamID", "KdfParameters", "PublicCustomData",
]
private let innerHeaderFieldNames = ["EndOfHeader", "InnerRandomStreamID", "InnerRandomStreamKey", "Binary"]

private struct OuterHeader {
    var cipherId: [UInt8] = []
    var compression: UInt32 = 0
    var masterSeed: [UInt8] = []
    var encryptionIV: [UInt8] = []
    var kdfParameters: [String: VarDictValue] = [:]
}

private struct InnerHeader {
    var crsAlgorithm: UInt32 = 0
    var protectedStreamKey: [UInt8] = []
}

public enum Kdbx4 {

    // MARK: - Chiavi derivate

    /// SHA-512(uint64LE(blockIndex) ++ baseKey) — usato sia per l'HMAC
    /// dell'header sia per l'HMAC di ciascun blocco del corpo cifrato.
    private static func hmacKeyForBlock(_ baseKey: [UInt8], _ blockIndex: UInt64) -> [UInt8] {
        let w = ByteWriter()
        w.writeUInt64LE(blockIndex)
        w.writeBytes(baseKey)
        return HashSHA512.hash(w.bytes)
    }

    private static func computeKeys(
        password: String,
        keyfile: [UInt8]?,
        masterSeed: [UInt8],
        kdfParameters: [String: VarDictValue]
    ) throws -> (cipherKey: [UInt8], hmacKeyBase: [UInt8]) {
        let passwordHash = HashSHA256.hash(Array(password.utf8))
        var composite = passwordHash
        if let keyfile = keyfile {
            composite += HashSHA256.hash(keyfile)
        }
        let credHash = HashSHA256.hash(composite)

        guard let uuidBytes = kdfParameters["$UUID"]?.asBytes else {
            throw Kdbx4Error.unsupportedKdf("nessun $UUID nei parametri KDF")
        }
        let kind: Argon2Kind
        if uuidBytes == KdbxIds.kdfArgon2id { kind = .argon2id }
        else if uuidBytes == KdbxIds.kdfArgon2d { kind = .argon2d }
        else { throw Kdbx4Error.unsupportedKdf("KDF AES legacy non supportato") }

        guard let salt = kdfParameters["S"]?.asBytes,
              let parallelism = kdfParameters["P"]?.asUInt32,
              let iterations = kdfParameters["I"]?.asUInt32,
              let memoryBytes = kdfParameters["M"]?.asUInt64,
              let version = kdfParameters["V"]?.asUInt32
        else {
            throw Kdbx4Error.corruptFile("parametri Argon2 mancanti o non validi")
        }

        let derived = try Argon2.hash(
            password: credHash, salt: salt,
            iterations: iterations, memoryKiB: UInt32(memoryBytes / 1024),
            parallelism: parallelism, outputLength: 32, kind: kind, version: version
        )

        var keyWithSeed = masterSeed
        keyWithSeed += derived
        keyWithSeed.append(0x01)

        let cipherKey = HashSHA256.hash(Array(keyWithSeed[0..<64]))
        let hmacKeyBase = HashSHA512.hash(keyWithSeed)
        return (cipherKey, hmacKeyBase)
    }

    // MARK: - Blocchi HMAC

    private static func hmacBlockDecrypt(_ data: [UInt8], hmacKeyBase: [UInt8]) throws -> [UInt8] {
        let r = ByteReader(data)
        var out: [UInt8] = []
        var blockIndex: UInt64 = 0
        while true {
            let blockHash = try r.readBytes(32)
            let blockLen = try Int(r.readUInt32LE())
            if blockLen == 0 { break }
            let blockData = try r.readBytes(blockLen)
            let blockKey = hmacKeyForBlock(hmacKeyBase, blockIndex)
            let w = ByteWriter()
            w.writeUInt64LE(blockIndex)
            w.writeUInt32LE(UInt32(blockLen))
            w.writeBytes(blockData)
            let calc = HMACSHA256.authenticate(key: blockKey, data: w.bytes)
            guard calc == blockHash else { throw Kdbx4Error.corruptFile("blocco HMAC \(blockIndex) non valido") }
            out += blockData
            blockIndex += 1
        }
        return out
    }

    private static func hmacBlockEncrypt(_ data: [UInt8], hmacKeyBase: [UInt8]) -> [UInt8] {
        let blockSize = 1024 * 1024
        let out = ByteWriter()
        var blockIndex: UInt64 = 0
        var pos = 0
        while pos < data.count {
            let end = min(pos + blockSize, data.count)
            let chunk = Array(data[pos..<end])
            let blockKey = hmacKeyForBlock(hmacKeyBase, blockIndex)
            let w = ByteWriter()
            w.writeUInt64LE(blockIndex)
            w.writeUInt32LE(UInt32(chunk.count))
            w.writeBytes(chunk)
            let hash = HMACSHA256.authenticate(key: blockKey, data: w.bytes)
            out.writeBytes(hash)
            out.writeUInt32LE(UInt32(chunk.count))
            out.writeBytes(chunk)
            blockIndex += 1
            pos = end
        }
        let finalKey = hmacKeyForBlock(hmacKeyBase, blockIndex)
        let wf = ByteWriter()
        wf.writeUInt64LE(blockIndex)
        wf.writeUInt32LE(0)
        let finalHash = HMACSHA256.authenticate(key: finalKey, data: wf.bytes)
        out.writeBytes(finalHash)
        out.writeUInt32LE(0)
        return out.bytes
    }

    // MARK: - Apertura

    public static func open(data: [UInt8], password: String, keyfile: [UInt8]? = nil) throws -> VaultDatabase {
        let r = ByteReader(data)
        let sig1 = try r.readUInt32LE()
        let sig2 = try r.readUInt32LE()
        guard sig1 == 0x9AA2_D903, sig2 == 0xB54B_FB67 else { throw Kdbx4Error.badSignature }
        let versionMinor = try r.readUInt16LE()
        let versionMajor = try r.readUInt16LE()
        guard versionMajor == 4 else {
            throw Kdbx4Error.unsupportedVersion(major: Int(versionMajor), minor: Int(versionMinor))
        }

        var header = OuterHeader()
        headerLoop: while true {
            let fieldId = try r.readByte()
            let size = try Int(r.readUInt32LE())
            let value = try r.readBytes(size)
            let name = Int(fieldId) < headerFieldNames.count ? headerFieldNames[Int(fieldId)] : "Unknown"
            switch name {
            case "EndOfHeader": break headerLoop
            case "CipherID": header.cipherId = value
            case "CompressionFlags": header.compression = try ByteReader(value).readUInt32LE()
            case "MasterSeed": header.masterSeed = value
            case "EncryptionIV": header.encryptionIV = value
            case "KdfParameters": header.kdfParameters = try VarDictionary.read(value)
            default: break
            }
        }
        let headerEndOffset = r.offset
        let headerBytes = Array(data[0..<headerEndOffset])

        let expectedHeaderSha = try r.readBytes(32)
        guard HashSHA256.hash(headerBytes) == expectedHeaderSha else {
            throw Kdbx4Error.corruptFile("hash dell'header non valido")
        }

        guard header.masterSeed.count == 32 else { throw Kdbx4Error.corruptFile("master seed non valido") }
        let (cipherKey, hmacKeyBase) = try computeKeys(
            password: password, keyfile: keyfile,
            masterSeed: header.masterSeed, kdfParameters: header.kdfParameters
        )

        let expectedHeaderHmac = try r.readBytes(32)
        let headerHmacKey = hmacKeyForBlock(hmacKeyBase, 0xFFFF_FFFF_FFFF_FFFF)
        let calcHeaderHmac = HMACSHA256.authenticate(key: headerHmacKey, data: headerBytes)
        guard calcHeaderHmac == expectedHeaderHmac else { throw Kdbx4Error.invalidPassword }

        let bodyEncrypted = r.readToEnd()
        let bodyCompressed = try hmacBlockDecrypt(bodyEncrypted, hmacKeyBase: hmacKeyBase)

        var bodyPlain: [UInt8]
        if header.cipherId == KdbxIds.cipherAES {
            guard header.encryptionIV.count == 16 else { throw Kdbx4Error.corruptFile("IV non valido") }
            bodyPlain = try AESCBC.decrypt(data: bodyCompressed, key: cipherKey, iv: header.encryptionIV)
        } else if header.cipherId == KdbxIds.cipherChaCha20 {
            // Cifrario esterno ChaCha20: 32 byte di chiave (= cipherKey) e 12 byte di nonce
            // ricavati dall'IV dell'header (spec KDBX: i primi 12 byte).
            guard header.encryptionIV.count >= 12 else { throw Kdbx4Error.corruptFile("IV ChaCha20 non valido") }
            let nonce = Array(header.encryptionIV[0..<12])
            bodyPlain = ChaCha20.xor(key: cipherKey, counter: 0, nonce: nonce, data: bodyCompressed)
        } else {
            throw Kdbx4Error.unsupportedCipher
        }

        if header.compression == 1 {
            bodyPlain = try GZip.decompress(bodyPlain)
        }

        let innerReader = ByteReader(bodyPlain)
        var inner = InnerHeader()
        innerLoop: while true {
            let fieldId = try innerReader.readByte()
            let size = try Int(innerReader.readUInt32LE())
            let value = try innerReader.readBytes(size)
            let name = Int(fieldId) < innerHeaderFieldNames.count ? innerHeaderFieldNames[Int(fieldId)] : "Unknown"
            switch name {
            case "EndOfHeader": break innerLoop
            case "InnerRandomStreamID": inner.crsAlgorithm = try ByteReader(value).readUInt32LE()
            case "InnerRandomStreamKey": inner.protectedStreamKey = value
            default: break // Binary e altri: ignorati in questo MVP
            }
        }
        let xmlBytes = innerReader.readToEnd()

        guard inner.crsAlgorithm == 3 else {
            throw Kdbx4Error.unsupportedKdf("algoritmo del flusso interno non supportato (atteso ChaCha20)")
        }
        let stream = ChaCha20ProtectStream(streamKey: inner.protectedStreamKey)

        return try XmlCodec.parse(xmlData: Data(xmlBytes), protectStream: stream)
    }

    // MARK: - Salvataggio

    public static func save(
        database: VaultDatabase,
        password: String,
        keyfile: [UInt8]? = nil,
        argonMemoryKiB: UInt32 = 64 * 1024,
        argonIterations: UInt32 = 3,
        argonParallelism: UInt32 = 4
    ) throws -> [UInt8] {
        let masterSeed = try randomBytes(32)
        let kdfSalt = try randomBytes(32)
        let encryptionIV = try randomBytes(16)
        let innerStreamKey = try randomBytes(64)

        let kdfParamsBytes = VarDictionary.write([
            ("$UUID", .bytes(KdbxIds.kdfArgon2id)),
            ("S", .bytes(kdfSalt)),
            ("P", .uint32(argonParallelism)),
            ("I", .uint64(UInt64(argonIterations))),
            ("M", .uint64(UInt64(argonMemoryKiB) * 1024)),
            ("V", .uint32(0x13)),
        ])

        func field(_ id: UInt8, _ data: [UInt8]) -> [UInt8] {
            let w = ByteWriter()
            w.writeByte(id)
            w.writeUInt32LE(UInt32(data.count))
            w.writeBytes(data)
            return w.bytes
        }

        var headerBytes: [UInt8] = []
        let sigW = ByteWriter()
        sigW.writeUInt32LE(0x9AA2_D903)
        sigW.writeUInt32LE(0xB54B_FB67)
        sigW.writeUInt16LE(0)
        sigW.writeUInt16LE(4)
        headerBytes += sigW.bytes
        headerBytes += field(2, KdbxIds.cipherAES)
        headerBytes += field(3, { let w = ByteWriter(); w.writeUInt32LE(1); return w.bytes }())
        headerBytes += field(4, masterSeed)
        headerBytes += field(7, encryptionIV)
        headerBytes += field(11, kdfParamsBytes)
        headerBytes += field(0, [0x0d, 0x0a, 0x0d, 0x0a])

        let (cipherKey, hmacKeyBase) = try computeKeys(
            password: password, keyfile: keyfile,
            masterSeed: masterSeed,
            kdfParameters: [
                "$UUID": .bytes(KdbxIds.kdfArgon2id), "S": .bytes(kdfSalt),
                "P": .uint32(argonParallelism), "I": .uint64(UInt64(argonIterations)),
                "M": .uint64(UInt64(argonMemoryKiB) * 1024), "V": .uint32(0x13),
            ]
        )

        let headerSha = HashSHA256.hash(headerBytes)
        let headerHmacKey = hmacKeyForBlock(hmacKeyBase, 0xFFFF_FFFF_FFFF_FFFF)
        let headerHmac = HMACSHA256.authenticate(key: headerHmacKey, data: headerBytes)

        let stream = ChaCha20ProtectStream(streamKey: innerStreamKey)
        let xmlData = try XmlCodec.serialize(database: database, protectStream: stream)

        var innerHeaderBytes: [UInt8] = []
        innerHeaderBytes += field(1, { let w = ByteWriter(); w.writeUInt32LE(3); return w.bytes }())
        innerHeaderBytes += field(2, innerStreamKey)
        innerHeaderBytes += field(0, [])

        let payload = innerHeaderBytes + Array(xmlData)
        let compressed = try GZip.compress(payload)
        let padded = try AESCBC.encrypt(data: compressed, key: cipherKey, iv: encryptionIV)
        let body = hmacBlockEncrypt(padded, hmacKeyBase: hmacKeyBase)

        var out: [UInt8] = []
        out += headerBytes
        out += headerSha
        out += headerHmac
        out += body
        return out
    }

    private static func randomBytes(_ count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw Kdbx4Error.corruptFile("generatore casuale non disponibile") }
        return bytes
    }
}
