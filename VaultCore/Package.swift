// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VaultCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "VaultCore", targets: ["VaultCore"]),
    ],
    targets: [
        // Implementazione di riferimento Argon2 (CC0/Apache-2.0), vendorizzata da
        // phc-winner-argon2. Vedi Sources/CArgon2/LICENSE-argon2.txt.
        .target(
            name: "CArgon2",
            path: "Sources/CArgon2",
            exclude: ["LICENSE-argon2.txt"],
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("blake2"),
            ]
        ),
        // Shim di sistema per CommonCrypto (serve solo per AES-256-CBC: SHA e
        // HMAC usano CryptoKit nativo, che non richiede alcun shim).
        .systemLibrary(
            name: "CCommonCrypto",
            path: "Sources/CCommonCrypto"
        ),
        .target(
            name: "VaultCore",
            dependencies: ["CArgon2", "CCommonCrypto"],
            path: "Sources/VaultCore"
        ),
        .testTarget(
            name: "VaultCoreTests",
            dependencies: ["VaultCore"],
            path: "Tests/VaultCoreTests"
        ),
        // Popola Hush con progetti finti per demo/video: `swift run SeedDemo`.
        // Non fa parte dell'app.
        .executableTarget(
            name: "SeedDemo",
            dependencies: ["VaultCore"],
            path: "Sources/SeedDemo"
        ),
    ]
)
