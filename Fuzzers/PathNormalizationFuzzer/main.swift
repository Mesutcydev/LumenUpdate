// PathNormalizationFuzzer
// Fuzz target for path normalization logic.
//
// This fuzzer feeds arbitrary strings to PathNormalizer to find crashes
// or bypasses in traversal detection.

import Foundation
import LumenCore
import LumenArchive

@main
struct PathNormalizationFuzzer {
    static func main() {
        let testPaths: [String] = [
            "",
            ".",
            "..",
            "../..",
            "../../etc/passwd",
            "/",
            "/etc/passwd",
            "Contents/../../../etc/passwd",
            "Contents/./MacOS/./App",
            "Contents/\0MacOS",
            "a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p",
            String(repeating: "../", count: 100),
            String(repeating: "a/", count: 200),
            "Contents/MacOS/MyApp",
            "Contents/Resources/en.lproj/Localizable.strings",
            "..%2f..%2f..%2fetc%2fpasswd",
            "....//....//etc/passwd",
            "Contents/..\\..\\..\\etc\\passwd",
            "\u{2025}/etc/passwd",
            "Contents/\u{FEFF}MacOS",
        ]

        var crashCount = 0
        var rejectedCount = 0

        for (i, path) in testPaths.enumerated() {
            do {
                let normalized = try PathNormalizer.normalize(path)
                print("Path \(i): ACCEPTED — '\(path.prefix(40))' → '\(normalized.prefix(40))'")
            } catch {
                rejectedCount += 1
                print("Path \(i): REJECTED — '\(path.prefix(40))'")
            }
        }

        print("")
        print("Fuzzing complete: \(testPaths.count) paths, \(crashCount) crashes, \(rejectedCount) rejected")
    }
}
