import Foundation

enum MessagePartKind { case text, image }

typealias MessagePart = (kind: MessagePartKind, value: String)

/// Remove image references (markdown images and data URIs) from text
func stripImagesFromText(_ text: String) -> String {
    let pattern = #"!\[[^\]]*\]\([^)]+\)|data:image\/[^;]+;base64,[A-Za-z0-9+/=\n]+"#
    let cleaned = (try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]))
        .map { $0.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "") } ?? text
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Parse message text into text and image parts
func parseMessageParts(_ text: String) -> [MessagePart] {
    var result: [MessagePart] = []
    let pattern = #"!\[[^\]]*\]\(([^)]+)\)|(?:^|\n)(data:image\/[^;]+;base64,[A-Za-z0-9+/=\n]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return [(.text, text)]
    }

    var lastEnd = text.startIndex
    let nsText = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

    for match in matches {
        guard let matchRange = Range(match.range, in: text) else { continue }
        if lastEnd < matchRange.lowerBound {
            let before = String(text[lastEnd..<matchRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty { result.append((.text, before)) }
        }
        if let urlRange = Range(match.range(at: 1), in: text) {
            result.append((.image, String(text[urlRange])))
        } else if let dataRange = Range(match.range(at: 2), in: text) {
            result.append((.image, String(text[dataRange])))
        }
        lastEnd = matchRange.upperBound
    }
    if lastEnd < text.endIndex {
        let remaining = String(text[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty { result.append((.text, remaining)) }
    }

    return result.isEmpty ? [(.text, text)] : result
}
