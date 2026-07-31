import Foundation
import LumenCore
import LumenInstall

public enum UpdateState: Sendable, Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(ReleaseInfo)
    case downloading(DownloadProgressInfo)
    case paused
    case verifying
    case readyToInstall(ReleaseInfo)
    case installing
    case relaunching
    case metadataStale(reason: String)
    case signatureInvalid(reason: String)
    case destinationNotWritable(path: String)
    case runningFromDiskImage
    case manualInstallationRequired(reason: String)
    case rolledBack(reason: String)
    case gatekeeperIntervention
    case keyRecoveryRequired
    case failed(LumenError)

    public var isTerminal: Bool {
        switch self {
        case .idle, .upToDate, .rolledBack, .failed:
            return true
        default:
            return false
        }
    }

    public var isActionable: Bool {
        switch self {
        case .updateAvailable, .readyToInstall, .manualInstallationRequired, .gatekeeperIntervention:
            return true
        default:
            return false
        }
    }
}

public struct ReleaseInfo: Sendable, Equatable {
    public let displayVersion: String
    public let bundleVersion: Int
    public let channel: String
    public let isCritical: Bool
    public let releaseNotesPath: String?
    public let targetPath: String
    public let targetHash: String
    public let targetSize: Int

    public init(
        displayVersion: String,
        bundleVersion: Int,
        channel: String,
        isCritical: Bool,
        releaseNotesPath: String?,
        targetPath: String,
        targetHash: String,
        targetSize: Int
    ) {
        self.displayVersion = displayVersion
        self.bundleVersion = bundleVersion
        self.channel = channel
        self.isCritical = isCritical
        self.releaseNotesPath = releaseNotesPath
        self.targetPath = targetPath
        self.targetHash = targetHash
        self.targetSize = targetSize
    }
}

public struct DownloadProgressInfo: Sendable, Equatable {
    public let bytesReceived: Int64
    public let totalBytes: Int64
    public let fractionComplete: Double

    public init(bytesReceived: Int64, totalBytes: Int64) {
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
        self.fractionComplete = totalBytes > 0 ? Double(bytesReceived) / Double(totalBytes) : 0
    }
}
