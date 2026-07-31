import Foundation
import LumenCore

public struct MigrationDiagnostics: Sendable {
    public let hasSparkleFramework: Bool
    public let hasLumenFramework: Bool
    public let hasBundledRoot: Bool
    public let sparkleAppcastURL: String?
    public let sparklePublicKey: String?
    public let migrationState: MigrationState

    public enum MigrationState: String, Sendable {
        case notStarted
        case bridgeReleaseInstalled
        case lumenInitialized
        case sparkleDisabled
        case sparkleRemoved
        case complete
    }

    public init(
        hasSparkleFramework: Bool,
        hasLumenFramework: Bool,
        hasBundledRoot: Bool,
        sparkleAppcastURL: String?,
        sparklePublicKey: String?,
        migrationState: MigrationState
    ) {
        self.hasSparkleFramework = hasSparkleFramework
        self.hasLumenFramework = hasLumenFramework
        self.hasBundledRoot = hasBundledRoot
        self.sparkleAppcastURL = sparkleAppcastURL
        self.sparklePublicKey = sparklePublicKey
        self.migrationState = migrationState
    }
}

public enum MigrationDiagnosticsRunner {

    public static func diagnose(bundlePath: String) -> MigrationDiagnostics {
        let fm = FileManager.default
        let frameworksPath = (bundlePath as NSString).appendingPathComponent("Contents/Frameworks")
        let resourcesPath = (bundlePath as NSString).appendingPathComponent("Contents/Resources")
        let infoPlistPath = (bundlePath as NSString).appendingPathComponent("Contents/Info.plist")

        let hasSparkle = fm.fileExists(atPath: (frameworksPath as NSString).appendingPathComponent("Sparkle.framework"))
        let hasLumen = fm.fileExists(atPath: (frameworksPath as NSString).appendingPathComponent("LumenUpdateSDK.framework"))
        let hasRoot = fm.fileExists(atPath: (resourcesPath as NSString).appendingPathComponent("root.json"))

        var appcastURL: String?
        var publicKey: String?

        if let infoDict = NSDictionary(contentsOfFile: infoPlistPath) as? [String: Any] {
            appcastURL = infoDict["SUFeedURL"] as? String
            publicKey = infoDict["SUPublicEDKey"] as? String
        }

        let state: MigrationDiagnostics.MigrationState
        if !hasSparkle && hasLumen {
            state = .complete
        } else if hasSparkle && hasLumen && hasRoot {
            state = .bridgeReleaseInstalled
        } else if hasSparkle && !hasLumen {
            state = .notStarted
        } else {
            state = .notStarted
        }

        return MigrationDiagnostics(
            hasSparkleFramework: hasSparkle,
            hasLumenFramework: hasLumen,
            hasBundledRoot: hasRoot,
            sparkleAppcastURL: appcastURL,
            sparklePublicKey: publicKey,
            migrationState: state
        )
    }

    public static func printReport(_ diagnostics: MigrationDiagnostics) {
        print("Lumen Migration Diagnostics")
        print("===========================")
        print("")
        print("  Sparkle framework:  \(diagnostics.hasSparkleFramework ? "present" : "absent")")
        print("  Lumen framework:    \(diagnostics.hasLumenFramework ? "present" : "absent")")
        print("  Bundled root:       \(diagnostics.hasBundledRoot ? "present" : "absent")")
        print("  Appcast URL:        \(diagnostics.sparkleAppcastURL ?? "not set")")
        print("  Sparkle public key: \(diagnostics.sparklePublicKey?.prefix(16) ?? "not set")...")
        print("  Migration state:    \(diagnostics.migrationState.rawValue)")
        print("")

        switch diagnostics.migrationState {
        case .notStarted:
            print("  Next: Create a bridge release with Lumen + Sparkle")
        case .bridgeReleaseInstalled:
            print("  Next: Lumen will initialize on next launch")
        case .lumenInitialized:
            print("  Next: Disable Sparkle in the next release")
        case .sparkleDisabled:
            print("  Next: Remove Sparkle framework")
        case .sparkleRemoved, .complete:
            print("  Migration complete. Lumen is the sole updater.")
        }
    }
}
