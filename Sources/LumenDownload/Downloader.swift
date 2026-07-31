import Foundation
import LumenCore

public struct DownloadProgress: Sendable {
    public let bytesReceived: Int64
    public let totalBytes: Int64
    public let fractionComplete: Double

    public init(bytesReceived: Int64, totalBytes: Int64) {
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
        self.fractionComplete = totalBytes > 0 ? Double(bytesReceived) / Double(totalBytes) : 0
    }
}

public struct DownloadResult: Sendable {
    public let fileURL: URL
    public let hash: String
    public let bytesDownloaded: Int64
    public let resumed: Bool

    public init(fileURL: URL, hash: String, bytesDownloaded: Int64, resumed: Bool) {
        self.fileURL = fileURL
        self.hash = hash
        self.bytesDownloaded = bytesDownloaded
        self.resumed = resumed
    }
}

public actor Downloader {
    private let configuration: DownloadConfiguration
    private let session: URLSession
    private var activeTask: URLSessionDownloadTask?
    private var isCancelled = false

    public init(configuration: DownloadConfiguration) {
        self.configuration = configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.timeoutInterval
        config.timeoutIntervalForResource = configuration.timeoutInterval * 2
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    public func download(
        from url: URL,
        to destinationDirectory: URL,
        progressHandler: (@Sendable (DownloadProgress) -> Void)? = nil
    ) async throws -> DownloadResult {
        try DownloadPolicy.validateURL(
            url,
            allowedHosts: configuration.allowedHosts,
            requireTLS: configuration.requireTLS
        )

        try preflightDiskSpace(destinationDirectory: destinationDirectory)

        var lastError: Error?
        for attempt in 0...configuration.maximumRetries {
            if isCancelled { throw LumenError.repositoryUnreachable("Download cancelled") }

            if attempt > 0 {
                let delay = RetryClassifier.delay(forAttempt: attempt - 1, baseDelay: configuration.retryBaseDelay)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            do {
                return try await performDownload(
                    from: url,
                    to: destinationDirectory,
                    progressHandler: progressHandler
                )
            } catch {
                lastError = error
                let classification = RetryClassifier.classify(error)
                if classification == .permanent {
                    throw error
                }
            }
        }

        throw lastError ?? LumenError.repositoryUnreachable("Download failed after \(configuration.maximumRetries) retries")
    }

    public func cancel() {
        isCancelled = true
        activeTask?.cancel()
    }

    private func performDownload(
        from url: URL,
        to destinationDirectory: URL,
        progressHandler: (@Sendable (DownloadProgress) -> Void)?
    ) async throws -> DownloadResult {
        let tempFile = destinationDirectory.appendingPathComponent("download-\(UUID().uuidString).tmp")
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let hasher = StreamingHasher()
        var bytesReceived: Int64 = 0
        var redirectCount = 0

        let delegate = DownloadDelegate(
            hasher: hasher,
            bytesReceived: { bytesReceived },
            setBytesReceived: { bytesReceived = $0 },
            expectedLength: Int64(configuration.expectedLength),
            maximumSize: Int64(configuration.maximumSize),
            redirectCount: { redirectCount },
            incrementRedirect: { redirectCount += 1 },
            maxRedirects: configuration.maximumRedirects,
            allowedHosts: configuration.allowedHosts,
            requireTLS: configuration.requireTLS,
            progressHandler: progressHandler
        )

        let delegateSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = delegateSession.downloadTask(with: url)
        activeTask = task

        let (tempURL, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
            delegate.completionHandler = { result in
                switch result {
                case .success(let url, let response):
                    continuation.resume(returning: (url, response))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            task.resume()
        }

        activeTask = nil

        guard let httpResponse = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: tempURL)
            throw LumenError.repositoryInvalidResponse("Non-HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw LumenError.repositoryInvalidResponse("HTTP \(httpResponse.statusCode)")
        }

        // Move to final destination
        let finalURL = destinationDirectory.appendingPathComponent("downloaded-\(UUID().uuidString).aar")
        try FileManager.default.moveItem(at: tempURL, to: finalURL)

        let hash = hasher.finalizeBase64URL()

        // Verify hash
        if let expectedSHA256 = configuration.expectedHashes["sha256"] {
            guard hash == expectedSHA256 else {
                try? FileManager.default.removeItem(at: finalURL)
                throw LumenError.targetHashMismatch(expected: expectedSHA256, actual: hash)
            }
        }

        // Verify length
        let fileSize = try FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int64 ?? 0
        guard fileSize == Int64(configuration.expectedLength) else {
            try? FileManager.default.removeItem(at: finalURL)
            throw LumenError.targetLengthMismatch(expected: configuration.expectedLength, actual: Int(fileSize))
        }

        return DownloadResult(
            fileURL: finalURL,
            hash: hash,
            bytesDownloaded: bytesReceived,
            resumed: false
        )
    }

    private func preflightDiskSpace(destinationDirectory: URL) throws {
        let requiredSpace = Int64(Double(configuration.expectedLength) * configuration.diskSpaceMultiplier)
        let values = try destinationDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        guard available >= requiredSpace else {
            throw LumenError.insufficientDiskSpace(required: requiredSpace, available: available)
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let hasher: StreamingHasher
    let bytesReceived: () -> Int64
    let setBytesReceived: (Int64) -> Void
    let expectedLength: Int64
    let maximumSize: Int64
    let redirectCount: () -> Int
    let incrementRedirect: () -> Void
    let maxRedirects: Int
    let allowedHosts: [String]
    let requireTLS: Bool
    let progressHandler: (@Sendable (DownloadProgress) -> Void)?
    var completionHandler: ((Result<(URL, URLResponse), Error>) -> Void)?

    init(
        hasher: StreamingHasher,
        bytesReceived: @escaping () -> Int64,
        setBytesReceived: @escaping (Int64) -> Void,
        expectedLength: Int64,
        maximumSize: Int64,
        redirectCount: @escaping () -> Int,
        incrementRedirect: @escaping () -> Void,
        maxRedirects: Int,
        allowedHosts: [String],
        requireTLS: Bool,
        progressHandler: (@Sendable (DownloadProgress) -> Void)?
    ) {
        self.hasher = hasher
        self.bytesReceived = bytesReceived
        self.setBytesReceived = setBytesReceived
        self.expectedLength = expectedLength
        self.maximumSize = maximumSize
        self.redirectCount = redirectCount
        self.incrementRedirect = incrementRedirect
        self.maxRedirects = maxRedirects
        self.allowedHosts = allowedHosts
        self.requireTLS = requireTLS
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Read the downloaded file and hash it
        do {
            let data = try Data(contentsOf: location)
            hasher.update(with: data)
            setBytesReceived(Int64(data.count))

            if Int64(data.count) > maximumSize {
                completionHandler?(.failure(LumenError.archiveExcessiveSize(actual: Int64(data.count), limit: maximumSize)))
                return
            }

            guard let response = downloadTask.response else {
                completionHandler?(.failure(LumenError.repositoryInvalidResponse("No response")))
                return
            }

            // Copy to a temp location that survives delegate deallocation
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent("lumen-download-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: location, to: tempURL)

            completionHandler?(.success((tempURL, response)))
        } catch {
            completionHandler?(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedLength
        progressHandler?(DownloadProgress(bytesReceived: totalBytesWritten, totalBytes: total))

        if totalBytesWritten > maximumSize {
            downloadTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        incrementRedirect()

        guard let newURL = request.url else {
            completionHandler(nil)
            return
        }

        do {
            try DownloadPolicy.validateRedirect(
                from: task.originalRequest?.url ?? newURL,
                to: newURL,
                allowedHosts: allowedHosts,
                requireTLS: requireTLS,
                redirectCount: redirectCount(),
                maxRedirects: maxRedirects
            )
            completionHandler(request)
        } catch {
            completionHandler(nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            completionHandler?(.failure(error))
        }
    }
}
