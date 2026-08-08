import Foundation

/// Cifrario a flusso ChaCha20 (RFC 8439), implementazione pura Swift.
///
/// Usato per proteggere/deproteggere i campi sensibili (es. Password) dentro
/// l'XML dei database KDBX4, esattamente come fa KeePass/kdbxweb.
///
/// Questa implementazione e' stata validata a parte (in un prototipo Python)
/// confrontando 200 combinazioni casuali di chiave/nonce/contatore/lunghezza
/// contro PyCryptodome, prima di essere trascritta qui 1:1 nella stessa
/// struttura di operazioni.
enum ChaCha20 {
    private static let constants: [UInt32] = [0x6170_7865, 0x3320_646e, 0x7962_2d32, 0x6b20_6574]

    @inline(__always)
    private static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x << n) | (x >> (32 - n))
    }

    @inline(__always)
    private static func quarterRound(_ s: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        s[a] = s[a] &+ s[b]; s[d] ^= s[a]; s[d] = rotl(s[d], 16)
        s[c] = s[c] &+ s[d]; s[b] ^= s[c]; s[b] = rotl(s[b], 12)
        s[a] = s[a] &+ s[b]; s[d] ^= s[a]; s[d] = rotl(s[d], 8)
        s[c] = s[c] &+ s[d]; s[b] ^= s[c]; s[b] = rotl(s[b], 7)
    }

    /// Genera un blocco di keystream a 64 byte per la data chiave (32 byte),
    /// contatore e nonce (12 byte).
    static func block(key: [UInt8], counter: UInt32, nonce: [UInt8]) -> [UInt8] {
        precondition(key.count == 32, "chiave ChaCha20 deve essere di 32 byte")
        precondition(nonce.count == 12, "nonce ChaCha20 deve essere di 12 byte")

        var state = [UInt32](repeating: 0, count: 16)
        state[0...3] = constants[0...3]
        for i in 0..<8 {
            state[4 + i] = UInt32(key[i * 4]) | (UInt32(key[i * 4 + 1]) << 8) |
                (UInt32(key[i * 4 + 2]) << 16) | (UInt32(key[i * 4 + 3]) << 24)
        }
        state[12] = counter
        for i in 0..<3 {
            state[13 + i] = UInt32(nonce[i * 4]) | (UInt32(nonce[i * 4 + 1]) << 8) |
                (UInt32(nonce[i * 4 + 2]) << 16) | (UInt32(nonce[i * 4 + 3]) << 24)
        }

        var working = state
        for _ in 0..<10 {
            quarterRound(&working, 0, 4, 8, 12)
            quarterRound(&working, 1, 5, 9, 13)
            quarterRound(&working, 2, 6, 10, 14)
            quarterRound(&working, 3, 7, 11, 15)
            quarterRound(&working, 0, 5, 10, 15)
            quarterRound(&working, 1, 6, 11, 12)
            quarterRound(&working, 2, 7, 8, 13)
            quarterRound(&working, 3, 4, 9, 14)
        }

        var out = [UInt8](repeating: 0, count: 64)
        for i in 0..<16 {
            let v = working[i] &+ state[i]
            out[i * 4] = UInt8(v & 0xff)
            out[i * 4 + 1] = UInt8((v >> 8) & 0xff)
            out[i * 4 + 2] = UInt8((v >> 16) & 0xff)
            out[i * 4 + 3] = UInt8((v >> 24) & 0xff)
        }
        return out
    }

    /// XOR di `data` con il keystream ChaCha20, a partire dal blocco `counter`.
    static func xor(key: [UInt8], counter: UInt32, nonce: [UInt8], data: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: data.count)
        var blockIndex = counter
        var offset = 0
        while offset < data.count {
            let ks = block(key: key, counter: blockIndex, nonce: nonce)
            let chunkLen = min(64, data.count - offset)
            for i in 0..<chunkLen {
                out[offset + i] = data[offset + i] ^ ks[i]
            }
            offset += chunkLen
            blockIndex &+= 1
        }
        return out
    }
}

/// Genera in ordine il keystream ChaCha20 usato per (de)proteggere i valori
/// `Protected="True"` nel documento XML del vault — consumato in sequenza
/// nell'ordine in cui i campi compaiono nel documento, come richiede il
/// formato KDBX.
final class ChaCha20ProtectStream {
    private let key: [UInt8]
    private let nonce: [UInt8]
    private var buffer: [UInt8] = []
    private var blockCounter: UInt32 = 0

    /// `streamKey` e' la chiave grezza salvata nell'header interno del kdbx
    /// (InnerRandomStreamKey); da questa si derivano chiave e nonce reali
    /// tramite SHA-512, come fa KeePass.
    init(streamKey: [UInt8]) {
        let hash = HashSHA512.hash(streamKey)
        self.key = Array(hash[0..<32])
        self.nonce = Array(hash[32..<44])
    }

    private func fill(_ n: Int) {
        while buffer.count < n {
            let ks = ChaCha20.block(key: key, counter: blockCounter, nonce: nonce)
            buffer.append(contentsOf: ks)
            blockCounter &+= 1
        }
    }

    func nextBytes(_ n: Int) -> [UInt8] {
        fill(n)
        let out = Array(buffer[0..<n])
        buffer.removeFirst(n)
        return out
    }

    /// XOR simmetrico: la stessa funzione protegge e deproteggere.
    func apply(to data: [UInt8]) -> [UInt8] {
        let ks = nextBytes(data.count)
        var out = [UInt8](repeating: 0, count: data.count)
        for i in 0..<data.count { out[i] = data[i] ^ ks[i] }
        return out
    }
}
