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
        .library(name: "LumenArchive", targets: ["LumenArchive"]),
        .library(name: "LumenInstall", targets: ["LumenInstall"]),
        .library(name: "LumenUpdateSDK", targets: ["LumenUpdateSDK"]),
        .library(name: "LumenUpdateUI", targets: ["LumenUpdateUI"]),
        .library(name: "LumenSparkleMigration", targets: ["LumenSparkleMigration"]),
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
            name: "LumenArchive",
            dependencies: ["LumenCore"]
        ),
        .target(
            name: "LumenInstall",
            dependencies: ["LumenCore", "LumenArchive"]
        ),
        .target(
            name: "LumenUpdateSDK",
            dependencies: [
                "LumenCore",
                "LumenTUF",
                "LumenCrypto",
                "LumenDownload",
                "LumenArchive",
                "LumenInstall",
            ]
        ),
        .target(
            name: "LumenUpdateUI",
            dependencies: ["LumenUpdateSDK"]
        ),
        .target(
            name: "LumenSparkleMigration",
            dependencies: ["LumenCore", "LumenTUF"]
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
        .testTarget(
            name: "LumenArchiveTests",
            dependencies: ["LumenArchive", "LumenTesting"]
        ),
        .testTarget(
            name: "LumenInstallTests",
            dependencies: ["LumenInstall", "LumenTesting"]
        ),
        .testTarget(
            name: "LumenUpdateSDKTests",
            dependencies: ["LumenUpdateSDK", "LumenTesting"]
        ),
        .testTarget(
            name: "LumenSparkleMigrationTests",
            dependencies: ["LumenSparkleMigration", "LumenTesting"]
        ),
    ]
)
