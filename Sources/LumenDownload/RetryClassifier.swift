import Foundation
import LumenCore

public enum RetryClassifier {

    public enum Classification: Sendable {
        case transient
        case permanent
    }

    public static func classify(_ error: Error) -> Classification {
        if let lumenError = error as? LumenError {
            switch lumenError {
            case .repositoryTimeout, .repositoryUnreachable:
                return .transient
            case .targetHashMismatch, .targetLengthMismatch,
                 .invalidSignature, .insufficientSignatures,
                 .expiredMetadata, .versionRollback,
                 .redirectDisallowed, .repositoryInvalidResponse:
                return .permanent
            default:
                return .permanent
            }
        }

        let nsError = error as NSError

        // Network-level transient errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorDNSLookupFailed:
                return .transient
            case NSURLErrorCancelled:
                return .permanent
            default:
                return .permanent
            }
        }

        return .permanent
    }

    public static func delay(forAttempt attempt: Int, baseDelay: TimeInterval) -> TimeInterval {
        return baseDelay * pow(2.0, Double(attempt))
    }
}
