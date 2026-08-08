import Foundation
import CArgon2

enum Argon2Error: Error {
    case failed(Int32)
    case unsupportedVersion(UInt32)
}

enum Argon2Kind {
    case argon2d
    case argon2id
}

/// Ponte verso l'implementazione di riferimento C di Argon2 (vendorizzata da
/// phc-winner-argon2, la stessa usata da libsodium/KeePass/kdbxweb).
enum Argon2 {
    static func hash(
        password: [UInt8],
        salt: [UInt8],
        iterations: UInt32,
        memoryKiB: UInt32,
        parallelism: UInt32,
        outputLength: Int,
        kind: Argon2Kind,
        version: UInt32
    ) throws -> [UInt8] {
        guard version == 0x13 else {
            // La libreria vendorizzata usa internamente ARGON2_VERSION_13;
            // i database KDBX4 moderni usano sempre questa versione.
            throw Argon2Error.unsupportedVersion(version)
        }

        var output = [UInt8](repeating: 0, count: outputLength)
        let status: Int32 = password.withUnsafeBufferPointer { pwdPtr in
            salt.withUnsafeBufferPointer { saltPtr in
                output.withUnsafeMutableBufferPointer { outPtr in
                    switch kind {
                    case .argon2d:
                        return argon2d_hash_raw(
                            iterations, memoryKiB, parallelism,
                            pwdPtr.baseAddress, pwdPtr.count,
                            saltPtr.baseAddress, saltPtr.count,
                            outPtr.baseAddress, outPtr.count
                        )
                    case .argon2id:
                        return argon2id_hash_raw(
                            iterations, memoryKiB, parallelism,
                            pwdPtr.baseAddress, pwdPtr.count,
                            saltPtr.baseAddress, saltPtr.count,
                            outPtr.baseAddress, outPtr.count
                        )
                    }
                }
            }
        }
        guard status == 0 else { throw Argon2Error.failed(status) }
        return output
    }
}
