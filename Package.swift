// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LumenUpdate",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LumenCore", targets: ["LumenCore"]),
        .library(name: "LumenTUF", targets: ["LumenTUF"]),
        .library(name: "LumenCrypto", targets: ["LumenCrypto"]),
        .library(name: "LumenTesting", targets: ["LumenTesting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "LumenCore"
        ),
        .target(
            name: "LumenTUF",
            dependencies: ["LumenCore", "LumenCrypto"]
        ),
        .target(
            name: "LumenCrypto",
            dependencies: [
                "LumenCore",
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .target(
            name: "LumenTesting",
            dependencies: ["LumenCore", "LumenCrypto", "LumenTUF"]
        ),
        .testTarget(
            name: "LumenCoreTests",
            dependencies: ["LumenCore", "LumenTesting"]
        ),
        .testTarget(
            name: "LumenTUFTFTests",
            dependencies: ["LumenTUF", "LumenTesting"]
        ),
        .testTarget(
            name: "LumenCryptoTests",
            dependencies: ["LumenCrypto", "LumenTesting"]
        ),
    ]
)
