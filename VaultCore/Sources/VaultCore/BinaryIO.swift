import Foundation

enum BinaryIOError: Error {
    case outOfBounds
}

/// Lettore binario little-endian minimale, sufficiente per il formato KDBX.
final class ByteReader {
    private let bytes: [UInt8]
    private(set) var offset: Int = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }
    init(_ data: Data) { self.bytes = Array(data) }

    var remaining: Int { bytes.count - offset }

    func readBytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= bytes.count else { throw BinaryIOError.outOfBounds }
        let slice = Array(bytes[offset..<offset + count])
        offset += count
        return slice
    }

    func readByte() throws -> UInt8 {
        try readBytes(1)[0]
    }

    func readUInt32LE() throws -> UInt32 {
        let b = try readBytes(4)
        return UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
    }

    func readUInt64LE() throws -> UInt64 {
        let b = try readBytes(8)
        var v: UInt64 = 0
        for i in (0..<8).reversed() { v = (v << 8) | UInt64(b[i]) }
        return v
    }

    func readInt32LE() throws -> Int32 { Int32(bitPattern: try readUInt32LE()) }
    func readInt64LE() throws -> Int64 { Int64(bitPattern: try readUInt64LE()) }
    func readUInt16LE() throws -> UInt16 {
        let b = try readBytes(2)
        return UInt16(b[0]) | (UInt16(b[1]) << 8)
    }

    func readToEnd() -> [UInt8] {
        let slice = Array(bytes[offset...])
        offset = bytes.count
        return slice
    }
}

/// Scrittore binario little-endian minimale.
final class ByteWriter {
    private(set) var bytes: [UInt8] = []

    func writeBytes(_ b: [UInt8]) { bytes.append(contentsOf: b) }
    func writeByte(_ b: UInt8) { bytes.append(b) }

    func writeUInt32LE(_ v: UInt32) {
        bytes.append(UInt8(v & 0xff))
        bytes.append(UInt8((v >> 8) & 0xff))
        bytes.append(UInt8((v >> 16) & 0xff))
        bytes.append(UInt8((v >> 24) & 0xff))
    }

    func writeUInt64LE(_ v: UInt64) {
        var x = v
        for _ in 0..<8 {
            bytes.append(UInt8(x & 0xff))
            x >>= 8
        }
    }

    func writeInt32LE(_ v: Int32) { writeUInt32LE(UInt32(bitPattern: v)) }
    func writeUInt16LE(_ v: UInt16) {
        bytes.append(UInt8(v & 0xff))
        bytes.append(UInt8((v >> 8) & 0xff))
    }
}
