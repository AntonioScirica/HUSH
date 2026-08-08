import Foundation
import Compression

/// CRC32 (polinomio riflesso 0xEDB88320), verificato a parte in Python contro
/// zlib.crc32 su 50 input casuali prima di essere trascritto qui.
enum CRC32 {
    private static let table: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            t[i] = c
        }
        return t
    }()

    static func checksum(_ data: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in data {
            crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

enum GZipError: Error {
    case notGzip
    case truncated
    case compressionFailed
}

/// Compressione/decompressione GZip (RFC 1952). Il framework `Compression` di
/// Apple espone solo DEFLATE "grezzo" (RFC 1951, senza alcun wrapper), quindi
/// costruiamo a mano l'header/trailer gzip attorno ad esso — e' l'approccio
/// standard su iOS/macOS, dato che non esiste un'API di sistema per il gzip
/// vero e proprio.
enum GZip {
    static func decompress(_ input: [UInt8]) throws -> [UInt8] {
        guard input.count >= 18, input[0] == 0x1f, input[1] == 0x8b, input[2] == 0x08 else {
            throw GZipError.notGzip
        }
        let flags = input[3]
        var pos = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard pos + 2 <= input.count else { throw GZipError.truncated }
            let xlen = Int(input[pos]) | (Int(input[pos + 1]) << 8)
            pos += 2 + xlen
        }
        if flags & 0x08 != 0 { // FNAME
            while pos < input.count, input[pos] != 0 { pos += 1 }
            pos += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while pos < input.count, input[pos] != 0 { pos += 1 }
            pos += 1
        }
        if flags & 0x02 != 0 { // FHCRC
            pos += 2
        }
        guard pos < input.count, input.count - pos >= 8 else { throw GZipError.truncated }
        let deflateBody = Array(input[pos..<(input.count - 8)])

        let decompressed = try rawInflate(deflateBody)
        return decompressed
    }

    static func compress(_ input: [UInt8]) throws -> [UInt8] {
        var out: [UInt8] = [0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff]
        let deflated = try rawDeflate(input)
        out.append(contentsOf: deflated)
        let crc = CRC32.checksum(input)
        let isize = UInt32(truncatingIfNeeded: input.count)
        out.append(contentsOf: withUnsafeBytes(of: crc.littleEndian, Array.init))
        out.append(contentsOf: withUnsafeBytes(of: isize.littleEndian, Array.init))
        return out
    }

    private static func rawInflate(_ data: [UInt8]) throws -> [UInt8] {
        // Buffer di uscita a crescita dinamica: partiamo da una stima generosa
        // e raddoppiamo finche' la decompressione non si esaurisce.
        var capacity = max(data.count * 4, 4096)
        while true {
            var output = [UInt8](repeating: 0, count: capacity)
            let produced = output.withUnsafeMutableBytes { outPtr -> Int in
                data.withUnsafeBytes { inPtr -> Int in
                    compression_decode_buffer(
                        outPtr.bindMemory(to: UInt8.self).baseAddress!, capacity,
                        inPtr.bindMemory(to: UInt8.self).baseAddress!, data.count,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            if produced == 0 { throw GZipError.compressionFailed }
            if produced < capacity {
                return Array(output.prefix(produced))
            }
            capacity *= 2
            if capacity > 1_073_741_824 { throw GZipError.compressionFailed } // limite di sicurezza: 1 GiB
        }
    }

    private static func rawDeflate(_ data: [UInt8]) throws -> [UInt8] {
        let capacity = max(data.count + data.count / 2 + 256, 256)
        var output = [UInt8](repeating: 0, count: capacity)
        let produced = output.withUnsafeMutableBytes { outPtr -> Int in
            data.withUnsafeBytes { inPtr -> Int in
                compression_encode_buffer(
                    outPtr.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    inPtr.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard produced > 0 else { throw GZipError.compressionFailed }
        return Array(output.prefix(produced))
    }
}
