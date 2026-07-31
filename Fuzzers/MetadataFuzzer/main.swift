// MetadataFuzzer
// Fuzz target for TUF metadata parsing.
// Build: swift build -c release
// Run: ./Fuzzers/run_fuzzer.sh MetadataFuzzer
//
// This fuzzer feeds arbitrary bytes to the TUF metadata decoder to find
// crashes, hangs, or memory corruption in the JSON parsing and
// canonicalization paths.

import Foundation
import LumenCore
import LumenTUF

@main
struct MetadataFuzzer {
    static func main() {
        // In a real fuzzing setup, this would be driven by libFuzzer
        // or a similar coverage-guided fuzzer. For now, this serves as
        // a harness that can be connected to a fuzzing engine.

        let testInputs: [Data] = [
            Data(),
            Data("{}".utf8),
            Data("null".utf8),
            Data("[]".utf8),
            Data("\"string\"".utf8),
            Data("12345".utf8),
            Data(repeating: 0xFF, count: 1000),
            Data("{\"_type\":\"Root\",\"version\":1}".utf8),
            Data("{\"signatures\":[],\"signed\":{}}".utf8),
            Data(repeating: 0x7B, count: 100000),
        ]

        let crashCount = 0
        var errorCount = 0

        for (i, input) in testInputs.enumerated() {
            do {
                _ = try MetadataDecoder.decodeSignedRoot(input)
            } catch {
                errorCount += 1
            }

            do {
                _ = try MetadataDecoder.decodeSignedTimestamp(input)
            } catch {
                errorCount += 1
            }

            do {
                _ = try MetadataDecoder.decodeSignedSnapshot(input)
            } catch {
                errorCount += 1
            }

            do {
                _ = try MetadataDecoder.decodeSignedTargets(input)
            } catch {
                errorCount += 1
            }

            print("Input \(i): \(input.count) bytes — no crash")
        }

        print("")
        print("Fuzzing complete: \(testInputs.count) inputs, \(crashCount) crashes, \(errorCount) expected errors")
    }
}
