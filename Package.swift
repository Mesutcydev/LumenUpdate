// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LumenUpdate",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LumenCore", targets: ["LumenCore"]),
        .library(name: "LumenTUF", targets: ["LumenTUF"]),
        .library(name: "LumenCrypto", targets: ["LumenCrypto"]),
        .library(name: "LumenDownload", targets: ["LumenDownload"]),
        .library(name: "LumenTesting", targets: ["LumenTesting"]),
        .executable(name: "lumen", targets: ["lumen"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
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
            name: "LumenDownload",
            dependencies: ["LumenCore"]
        ),
        .target(
            name: "LumenTesting",
            dependencies: ["LumenCore", "LumenCrypto", "LumenTUF"]
        ),
        .executableTarget(
            name: "lumen",
            dependencies: [
                "LumenCore",
                "LumenTUF",
                "LumenCrypto",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
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
        .testTarget(
            name: "LumenDownloadTests",
            dependencies: ["LumenDownload", "LumenTesting"]
        ),
    ]
)
