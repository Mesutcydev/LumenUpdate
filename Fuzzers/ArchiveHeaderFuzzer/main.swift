// ArchiveHeaderFuzzer
// Fuzz target for archive entry validation.
//
// This fuzzer feeds arbitrary ArchiveEntryInfo values to the validator
// to find crashes or logic errors in path normalization, symlink
// validation, and size accounting.

import Foundation
import LumenCore
import LumenArchive

@main
struct ArchiveHeaderFuzzer {
    static func main() {
        let testEntries: [ArchiveEntryInfo] = [
            ArchiveEntryInfo(path: "", type: .file, mode: 0o644, size: 0),
            ArchiveEntryInfo(path: "/", type: .file, mode: 0o644, size: 0),
            ArchiveEntryInfo(path: "..", type: .file, mode: 0o644, size: 0),
            ArchiveEntryInfo(path: "../../../etc/passwd", type: .file, mode: 0o644, size: 0),
            ArchiveEntryInfo(path: "Contents/\0MacOS", type: .file, mode: 0o644, size: 0),
            ArchiveEntryInfo(path: String(repeating: "a", count: 2000), type: .file, mode: 0o644, size: 0),
            ArchiveEntryInfo(path: "Contents/MacOS/App", type: .file, mode: 0o4755, size: 100),
            ArchiveEntryInfo(path: "Contents/MacOS/App", type: .file, mode: 0o2755, size: 100),
            ArchiveEntryInfo(path: "link", type: .symlink, mode: 0o777, size: 0, symlinkTarget: "../../../etc/passwd"),
            ArchiveEntryInfo(path: "link", type: .symlink, mode: 0o777, size: 0, symlinkTarget: "/etc/passwd"),
            ArchiveEntryInfo(path: "dev", type: .device, mode: 0o600, size: 0),
            ArchiveEntryInfo(path: "sock", type: .socket, mode: 0o600, size: 0),
            ArchiveEntryInfo(path: "fifo", type: .fifo, mode: 0o600, size: 0),
            ArchiveEntryInfo(path: "hard", type: .hardlink, mode: 0o644, size: 0),
            ArchiveEntryInfo(path: "big", type: .file, mode: 0o644, size: Int64.max),
        ]

        let crashCount = 0
        var rejectedCount = 0

        for (i, entry) in testEntries.enumerated() {
            var seen = Set<String>()
            var totalSize: Int64 = 0
            do {
                try ArchiveEntryValidator.validateEntry(
                    entry, limits: .default, stagingRoot: "/tmp/staging",
                    seenPaths: &seen, totalUncompressedSize: &totalSize
                )
                print("Entry \(i): ACCEPTED — \(entry.path.prefix(50))")
            } catch {
                rejectedCount += 1
                print("Entry \(i): REJECTED — \(entry.path.prefix(50)) — \(error)")
            }
        }

        print("")
        print("Fuzzing complete: \(testEntries.count) entries, \(crashCount) crashes, \(rejectedCount) rejected")
    }
}
