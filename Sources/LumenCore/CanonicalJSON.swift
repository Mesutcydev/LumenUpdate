// CanonicalJSON.swift
// RFC 8785 JSON Canonicalization Scheme (JCS) implementation
//
// Reference: https://www.rfc-editor.org/info/rfc8785
//
// Canonicalization rules implemented:
// 1. Object keys are sorted lexicographically by Unicode code point.
// 2. No insignificant whitespace.
// 3. Numbers serialized per ECMAScript (RFC 8785 §3.2.2.3).
// 4. Strings use JSON escaping, with optional \uXXXX for non-ASCII.
// 5. Arrays preserve order.

import Foundation

public enum CanonicalJSON {

    /// Encode a Swift value to canonical JSON bytes per RFC 8785.
    /// Supported value types: NSNull, Bool, Int, UInt, Double, String, Array, Dictionary.
    /// Dictionary keys must be String.
    public static func encode(_ value: Any) throws -> Data {
        var buffer = ""
        try writeCanonical(value, into: &buffer)
        return Data(buffer.utf8)
    }

    /// Encode a value to a canonical JSON string.
    public static func encodeToString(_ value: Any) throws -> String {
        var buffer = ""
        try writeCanonical(value, into: &buffer)
        return buffer
    }

    /// Internal recursive writer.
    private static func writeCanonical(_ value: Any, into buffer: inout String) throws {
        // Unwrap NSNull
        if value is NSNull {
            buffer.append("null")
            return
        }

        // Optional handling
        if let optional = value as? OptionalValue {
            if optional.isNil {
                buffer.append("null")
            } else {
                try writeCanonical(optional.unwrap()!, into: &buffer)
            }
            return
        }

        // Handle NSNumber carefully: distinguish Bool from Int from Double
        if let num = value as? NSNumber {
            // Check the Objective-C type encoding to distinguish Bool from numeric
            let typeChar = String(cString: num.objCType)
            if typeChar == "c" || typeChar == "B" {
                // Bool
                buffer.append(num.boolValue ? "true" : "false")
                return
            } else if typeChar == "i" || typeChar == "l" || typeChar == "q" ||
                      typeChar == "s" || typeChar == "I" || typeChar == "L" ||
                      typeChar == "Q" || typeChar == "S" {
                // Integer
                buffer.append(String(num.intValue))
                return
            } else {
                // Double / Float
                buffer.append(formatNumber(num.doubleValue))
                return
            }
        }

        // Swift Bool (separate from NSNumber bridging)
        if let b = value as? Bool {
            buffer.append(b ? "true" : "false")
            return
        }

        // Integer types
        if let i = value as? Int {
            buffer.append(String(i))
            return
        }
        if let i = value as? Int64 {
            buffer.append(String(i))
            return
        }
        if let i = value as? UInt {
            buffer.append(String(i))
            return
        }
        if let i = value as? UInt64 {
            buffer.append(String(i))
            return
        }

        // Double (use ECMAScript number formatting)
        if let d = value as? Double {
            buffer.append(formatNumber(d))
            return
        }

        // String
        if let s = value as? String {
            buffer.append(escapeString(s))
            return
        }

        // Array
        if let arr = value as? [Any] {
            buffer.append("[")
            for (idx, item) in arr.enumerated() {
                if idx > 0 { buffer.append(",") }
                try writeCanonical(item, into: &buffer)
            }
            buffer.append("]")
            return
        }

        // Dictionary (keys MUST be strings; sorted lexicographically)
        if let dict = value as? [String: Any] {
            let sortedKeys = dict.keys.sorted { lhs, rhs in
                return lhs < rhs
            }
            buffer.append("{")
            for (idx, key) in sortedKeys.enumerated() {
                if idx > 0 { buffer.append(",") }
                buffer.append(escapeString(key))
                buffer.append(":")
                try writeCanonical(dict[key]!, into: &buffer)
            }
            buffer.append("}")
            return
        }

        throw LumenError.invalidJSON("Unsupported value type: \(type(of: value))")
    }

    /// Format a Double per ECMAScript / RFC 8785 §3.2.2.3.
    /// For integers representable as Int64, emit without decimal point.
    /// Otherwise use a round-trip representation, stripping trailing zeros.
    private static func formatNumber(_ d: Double) -> String {
        if d.isNaN || d.isInfinite {
            // RFC 8785 doesn't define these, but we follow common implementations
            // and reject them at decode time. For safety, emit "null" so verification fails clearly.
            return "null"
        }
        if d == d.rounded() && abs(d) < 1e15 {
            // Integer-valued double: emit as integer.
            return String(Int64(d))
        }
        // Use shortest round-trip representation.
        // Swift's default String(d) gives a round-trip representation.
        // We must strip trailing zeros after decimal point and handle exponent formatting.
        var s = String(format: "%.17g", d)
        // Convert "1e+05" to "100000"; "1e-05" to "0.00001".
        if s.contains("e") || s.contains("E") {
            // Use NumberFormatter or a manual approach.
            if let decimal = Decimal(string: String(d)) {
                var decString = "\(decimal)"
                // Decimal normalizes scientific notation to fixed.
                // Strip trailing zeros after decimal point.
                if decString.contains(".") {
                    while decString.hasSuffix("0") {
                        decString.removeLast()
                    }
                    if decString.hasSuffix(".") {
                        decString.removeLast()
                    }
                }
                return decString
            }
        } else if s.contains(".") {
            // Strip trailing zeros after decimal point.
            while s.hasSuffix("0") {
                s.removeLast()
            }
            if s.hasSuffix(".") {
                s.removeLast()
            }
        }
        return s
    }

    /// Escape a string per JSON spec (RFC 8259) with optional \uXXXX for
    /// non-ASCII characters (RFC 8785 §3.2.2.2).
    private static func escapeString(_ s: String) -> String {
        var result = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\":
                result.append("\\\\")
            case "\"":
                result.append("\\\"")
            case "\u{08}":
                result.append("\\b")
            case "\u{0C}":
                result.append("\\f")
            case "\n":
                result.append("\\n")
            case "\r":
                result.append("\\r")
            case "\t":
                result.append("\\t")
            default:
                if scalar.value < 0x20 {
                    result.append(String(format: "\\u%04x", scalar.value))
                } else if scalar.value < 0x80 {
                    result.append(Character(scalar))
                } else {
                    // RFC 8785: use \uXXXX for non-ASCII to ensure deterministic
                    // output across encodings.
                    result.append(String(format: "\\u%04x", scalar.value))
                }
            }
        }
        result.append("\"")
        return result
    }
}

// MARK: - Optional value handling

/// Protocol to support Any? values in canonical JSON.
private protocol OptionalValue {
    var isNil: Bool { get }
    func unwrap() -> Any?
}

extension Optional: OptionalValue {
    var isNil: Bool { self == nil }
    func unwrap() -> Any? { self }
}
