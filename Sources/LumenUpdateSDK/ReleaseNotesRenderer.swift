import Foundation
import LumenCore

public enum ReleaseNotesRenderer {

    public static func render(_ markdown: String) -> String {
        var result = markdown

        // Strip script tags and event handlers (invariant 8)
        result = stripHTMLTags(result)
        result = stripEventHandlers(result)
        result = stripJavascriptURLs(result)

        return result
    }

    public static func renderToAttributedString(_ markdown: String) -> NSAttributedString {
        let sanitized = render(markdown)
        return NSAttributedString(string: sanitized)
    }

    private static func stripHTMLTags(_ input: String) -> String {
        var result = input

        // First strip script/style tags AND their content
        let scriptPattern = "<script[^>]*>[\\s\\S]*?</script>"
        if let scriptRegex = try? NSRegularExpression(pattern: scriptPattern, options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = scriptRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        let stylePattern = "<style[^>]*>[\\s\\S]*?</style>"
        if let styleRegex = try? NSRegularExpression(pattern: stylePattern, options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = styleRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }

        // Then strip remaining HTML tags
        let tagPattern = "<[^>]*>"
        if let regex = try? NSRegularExpression(pattern: tagPattern, options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        return result
    }

    private static func stripEventHandlers(_ input: String) -> String {
        var result = input
        let patterns = [
            "on\\w+\\s*=\\s*\"[^\"]*\"",
            "on\\w+\\s*=\\s*'[^']*'",
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }
        return result
    }

    private static func stripJavascriptURLs(_ input: String) -> String {
        var result = input
        let pattern = "javascript\\s*:"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        return result
    }
}
