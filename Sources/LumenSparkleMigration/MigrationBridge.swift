import Foundation
import LumenCore
import LumenTUF

public struct MigrationPlan: Sendable {
    public let productID: String
    public let bridgeVersion: Int
    public let bridgeShortVersion: String
    public let sparkleReleases: [SparkleAppcastItem]
    public let lumenRootMetadata: Data
    public let steps: [MigrationStep]

    public init(
        productID: String,
        bridgeVersion: Int,
        bridgeShortVersion: String,
        sparkleReleases: [SparkleAppcastItem],
        lumenRootMetadata: Data,
        steps: [MigrationStep]
    ) {
        self.productID = productID
        self.bridgeVersion = bridgeVersion
        self.bridgeShortVersion = bridgeShortVersion
        self.sparkleReleases = sparkleReleases
        self.lumenRootMetadata = lumenRootMetadata
        self.steps = steps
    }
}

public struct MigrationStep: Sendable, Equatable {
    public let order: Int
    public let description: String
    public let isComplete: Bool

    public init(order: Int, description: String, isComplete: Bool = false) {
        self.order = order
        self.description = description
        self.isComplete = isComplete
    }
}

public enum MigrationBridge {

    public static func createMigrationPlan(
        appcast: SparkleAppcast,
        productID: String,
        lumenRootMetadata: Data
    ) -> MigrationPlan {
        let sortedReleases = appcast.items.sorted {
            (Int($0.version) ?? 0) > (Int($1.version) ?? 0)
        }

        let bridgeVersion = (Int(sortedReleases.first?.version ?? "0") ?? 0) + 1
        let bridgeShortVersion = sortedReleases.first?.shortVersion ?? "\(bridgeVersion)"

        let steps: [MigrationStep] = [
            MigrationStep(order: 1, description: "Build bridge release containing Lumen framework and bundled root metadata"),
            MigrationStep(order: 2, description: "Sign bridge release with existing Sparkle Ed25519 key"),
            MigrationStep(order: 3, description: "Publish bridge release via Sparkle appcast"),
            MigrationStep(order: 4, description: "Wait for users to update to bridge release"),
            MigrationStep(order: 5, description: "Lumen initializes and stores trusted root on first launch"),
            MigrationStep(order: 6, description: "Publish next release via Lumen (Sparkle retained but disabled)"),
            MigrationStep(order: 7, description: "Remove Sparkle framework in subsequent release"),
        ]

        return MigrationPlan(
            productID: productID,
            bridgeVersion: bridgeVersion,
            bridgeShortVersion: bridgeShortVersion,
            sparkleReleases: sortedReleases,
            lumenRootMetadata: lumenRootMetadata,
            steps: steps
        )
    }

    public static func validateBridgeRelease(
        bundlePath: String,
        expectedRootMetadata: Data
    ) throws -> Bool {
        let fm = FileManager.default
        let frameworksPath = (bundlePath as NSString).appendingPathComponent("Contents/Frameworks")

        // Check Lumen framework is embedded
        let lumenFramework = (frameworksPath as NSString).appendingPathComponent("LumenUpdateSDK.framework")
        guard fm.fileExists(atPath: lumenFramework) else {
            throw LumenError.missingField("LumenUpdateSDK.framework not found in bridge release")
        }

        // Check root metadata is bundled
        let resourcesPath = (bundlePath as NSString).appendingPathComponent("Contents/Resources")
        let rootPath = (resourcesPath as NSString).appendingPathComponent("root.json")
        guard fm.fileExists(atPath: rootPath) else {
            throw LumenError.missingField("root.json not found in bridge release Resources")
        }

        let bundledRoot = try Data(contentsOf: URL(fileURLWithPath: rootPath))
        guard bundledRoot == expectedRootMetadata else {
            throw LumenError.invalidMetadataFormat("Bundled root metadata does not match expected")
        }

        return true
    }

    public static func canMigrateWithoutSparkleKey() -> Bool {
        return false
    }
}
