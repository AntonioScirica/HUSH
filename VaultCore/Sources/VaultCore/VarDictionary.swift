import Foundation

/// Valore tipizzato del "VarDictionary" usato per i parametri KDF nell'header
/// KDBX4 (una piccola mappa nome -> valore con tipo esplicito, come da spec).
enum VarDictValue {
    case uint32(UInt32)
    case uint64(UInt64)
    case int32(Int32)
    case int64(Int64)
    case bool(Bool)
    case string(String)
    case bytes([UInt8])

    var typeByte: UInt8 {
        switch self {
        case .uint32: return 0x04
        case .uint64: return 0x05
        case .bool: return 0x08
        case .int32: return 0x0c
        case .int64: return 0x0d
        case .string: return 0x18
        case .bytes: return 0x42
        }
    }

    var asUInt64: UInt64? {
        switch self {
        case .uint32(let v): return UInt64(v)
        case .uint64(let v): return v
        case .int32(let v): return UInt64(v)
        case .int64(let v): return UInt64(v)
        default: return nil
        }
    }

    var asUInt32: UInt32? {
        guard let v = asUInt64 else { return nil }
        return UInt32(truncatingIfNeeded: v)
    }

    var asBytes: [UInt8]? {
        if case .bytes(let b) = self { return b }
        return nil
    }

    fileprivate var encodedPayload: [UInt8] {
        switch self {
        case .uint32(let v):
            let w = ByteWriter(); w.writeUInt32LE(v); return w.bytes
        case .uint64(let v):
            let w = ByteWriter(); w.writeUInt64LE(v); return w.bytes
        case .int32(let v):
            let w = ByteWriter(); w.writeInt32LE(v); return w.bytes
        case .int64(let v):
            let w = ByteWriter(); w.writeUInt64LE(UInt64(bitPattern: v)); return w.bytes
        case .bool(let v):
            return [v ? 1 : 0]
        case .string(let v):
            return Array(v.utf8)
        case .bytes(let v):
            return v
        }
    }
}

enum VarDictionary {
    /// Legge la mappa dei parametri KDF dal blob binario dell'header.
    static func read(_ data: [UInt8]) throws -> [String: VarDictValue] {
        let r = ByteReader(data)
        _ = try r.readUInt16LE() // versione del formato var-dictionary (0x0001)
        var out: [String: VarDictValue] = [:]
        while true {
            let typeByte = try r.readByte()
            if typeByte == 0 { break }
            let nameLen = try r.readUInt32LE()
            let nameBytes = try r.readBytes(Int(nameLen))
            guard let name = String(bytes: nameBytes, encoding: .utf8) else {
                throw Kdbx4Error.corruptFile("nome parametro KDF non valido")
            }
            let valLen = try r.readUInt32LE()
            let valBytes = try r.readBytes(Int(valLen))
            let value: VarDictValue
            switch typeByte {
            case 0x04: value = .uint32(ByteReader(valBytes).readLEUInt32Unsafe())
            case 0x05: value = .uint64(ByteReader(valBytes).readLEUInt64Unsafe())
            case 0x08: value = .bool(valBytes.first != 0)
            case 0x0c: value = .int32(Int32(bitPattern: ByteReader(valBytes).readLEUInt32Unsafe()))
            case 0x0d: value = .int64(Int64(bitPattern: ByteReader(valBytes).readLEUInt64Unsafe()))
            case 0x18: value = .string(String(bytes: valBytes, encoding: .utf8) ?? "")
            case 0x42: value = .bytes(valBytes)
            default: throw Kdbx4Error.corruptFile("tipo parametro KDF sconosciuto: \(typeByte)")
            }
            out[name] = value
        }
        return out
    }

    /// Scrive la mappa dei parametri KDF nel formato binario del var-dictionary.
    static func write(_ dict: [(String, VarDictValue)]) -> [UInt8] {
        let w = ByteWriter()
        w.writeUInt16LE(0x0001)
        for (name, value) in dict {
            w.writeByte(value.typeByte)
            let nameBytes = Array(name.utf8)
            w.writeUInt32LE(UInt32(nameBytes.count))
            w.writeBytes(nameBytes)
            let payload = value.encodedPayload
            w.writeUInt32LE(UInt32(payload.count))
            w.writeBytes(payload)
        }
        w.writeByte(0)
        return w.bytes
    }
}

private extension ByteReader {
    /// Helper "senza throw" per blocchi di byte gia' verificati in lunghezza.
    func readLEUInt32Unsafe() -> UInt32 { (try? readUInt32LE()) ?? 0 }
    func readLEUInt64Unsafe() -> UInt64 { (try? readUInt64LE()) ?? 0 }
}
