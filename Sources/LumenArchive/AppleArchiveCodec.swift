import Foundation
import System
import AppleArchive
import LumenCore

/// Encodes and decodes Apple Archive (`.aar`) files, the first-class Lumen
/// update format (ADR-002). Apple Archive preserves ownership, permissions,
/// flags, timestamps, and extended attributes — which plain tar does not.
///
/// Encoding uses LZFSE compression. Decoding extracts to an isolated staging
/// directory; security validation is performed by the caller (SafeExtractor)
/// AFTER extraction into that isolated directory.
public enum AppleArchiveCodec {

    // Attribute key set preserving type, path, link, device, data, uid, gid,
    // mode, flags, and creation/modification/change timestamps.
    // From Apple sample code: developer.apple.com/documentation/accelerate/compressing_file_system_directories
    private static let keySet = ArchiveHeader.FieldKeySet("TYP,PAT,LNK,DEV,DAT,UID,GID,MOD,FLG,MTM,BTM,CTM")!

    /// Encode a directory tree into a compressed `.aar` archive.
    public static func encode(directory: URL, to archiveURL: URL) throws {
        let archivePath = FilePath(archiveURL.path)
        let dirPath = FilePath(directory.path)

        // withFileStream's .create makes the file but not its parent directory.
        try FileManager.default.createDirectory(
            at: archiveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try ArchiveByteStream.withFileStream(
                path: archivePath,
                mode: .writeOnly,
                options: [.create, .truncate],
                permissions: FilePermissions(rawValue: 0o644)
            ) { writeFileStream in
                try ArchiveByteStream.withCompressionStream(using: .lzfse, writingTo: writeFileStream) { compStream in
                    try ArchiveStream.withEncodeStream(writingTo: compStream) { encodeStream in
                        try encodeStream.writeDirectoryContents(archiveFrom: dirPath, keySet: keySet)
                    }
                }
            }
        } catch {
            throw LumenError.archiveMalformed("Apple Archive encode failed: \(error)")
        }
    }

    /// Decode a `.aar` archive into a destination directory using the framework's
    /// extraction (preserves attributes). The destination should be an isolated
    /// staging directory; the caller validates its contents afterward.
    public static func extract(archive: URL, to destination: URL) throws {
        let archivePath = FilePath(archive.path)
        let destPath = FilePath(destination.path)

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            try ArchiveByteStream.withFileStream(
                path: archivePath,
                mode: .readOnly,
                options: [],
                permissions: FilePermissions(rawValue: 0o644)
            ) { readFileStream in
                try ArchiveByteStream.withDecompressionStream(readingFrom: readFileStream) { decompStream in
                    try ArchiveStream.withDecodeStream(readingFrom: decompStream) { decodeStream in
                        try ArchiveStream.withExtractStream(
                            extractingTo: destPath,
                            flags: [.ignoreOperationNotPermitted]
                        ) { extractStream in
                            _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream)
                        }
                    }
                }
            }
        } catch {
            throw LumenError.archiveMalformed("Apple Archive decode failed: \(error)")
        }
    }

    /// Returns true if the file at the URL appears to be an Apple Archive
    /// (by `.aar` extension).
    public static func isAppleArchive(_ url: URL) -> Bool {
        return url.pathExtension.lowercased() == "aar"
    }
}
