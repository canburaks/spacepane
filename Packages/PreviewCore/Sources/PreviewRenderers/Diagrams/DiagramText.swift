import CoreGraphics
import CoreText
import Foundation

/// Label cleanup shared by every diagram language. Labels are document content: they are shown as
/// plain text only (no markup is interpreted, no link or image is followed) and are bounded.
enum DiagramText {
    /// Plain text lines for a label: line-break tags become breaks, other inline tags are
    /// dropped, entity codes are decoded, and the result is bounded in characters and lines.
    static func lines(from raw: String, stripsTags: Bool = true, hashEntities: Bool = true) -> [String] {
        var text = raw
        // Markdown strings arrive wrapped in backticks; the formatting itself is not applied.
        if text.count >= 2, text.hasPrefix("`"), text.hasSuffix("`") { text = String(text.dropFirst().dropLast()) }
        let converted = stripsTags ? removeTags(text) : text
        let decoded = decodeEntities(converted, hashCodes: hashEntities)
        var result: [String] = []
        var remaining = DiagramLimits.maximumLabelCharacters
        for piece in decoded.components(separatedBy: "\n") {
            let line = piece.trimmingCharacters(in: .whitespaces)
            if line.isEmpty, result.isEmpty { continue }
            guard remaining > 0, result.count < DiagramLimits.maximumLabelLines else {
                result.append("…")
                break
            }
            if line.count > remaining {
                result.append(String(line.prefix(remaining)) + "…")
                remaining = 0
            } else {
                result.append(line)
                remaining -= line.count
            }
        }
        while result.last?.isEmpty == true { result.removeLast() }
        return result
    }

    static func singleLine(from raw: String) -> String {
        lines(from: raw).joined(separator: " ")
    }

    /// Replaces `<br>` style breaks with newlines and removes other tags of a conservative shape.
    static func removeTags(_ text: String) -> String {
        guard text.contains("<") else { return text }
        let scalars = Array(text.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            guard scalar == "<" else { output.append(scalar); index += 1; continue }
            // A tag is "<" or "</" followed by a letter, ending at ">" within a short distance.
            var cursor = index + 1
            if cursor < scalars.count, scalars[cursor] == "/" { cursor += 1 }
            guard cursor < scalars.count, scalars[cursor].properties.isAlphabetic,
                  let close = (cursor..<min(scalars.count, index + 120)).first(where: { scalars[$0] == ">" }) else {
                output.append(scalar)
                index += 1
                continue
            }
            let name = String(String.UnicodeScalarView(scalars[cursor..<close]))
                .lowercased().prefix { $0.isLetter || $0.isNumber }
            if breakingTags.contains(String(name)) { output.append("\n") }
            index = close + 1
        }
        return String(output)
    }

    private static let breakingTags: Set<String> = ["br", "div", "p", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6"]

    /// Mermaid entity codes (`#35;`, `#quot;`) and the common HTML entities.
    /// `hashCodes` enables the Mermaid `#35;` spelling; draw.io labels use only `&` entities.
    static func decodeEntities(_ text: String, hashCodes: Bool = true) -> String {
        guard (hashCodes && text.contains("#")) || text.contains("&") else { return text }
        let scalars = Array(text.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            guard scalar == "&" || (hashCodes && scalar == "#") else { output.append(scalar); index += 1; continue }
            let limit = min(scalars.count, index + 12)
            guard let end = ((index + 1)..<limit).first(where: { scalars[$0] == ";" }), end > index + 1 else {
                output.append(scalar)
                index += 1
                continue
            }
            let name = String(String.UnicodeScalarView(scalars[(index + 1)..<end]))
            if let decoded = entity(name) {
                output.append(decoded)
                index = end + 1
            } else {
                output.append(scalar)
                index += 1
            }
        }
        return String(output)
    }

    private static func entity(_ name: String) -> Unicode.Scalar? {
        if name.hasPrefix("#") || name.hasPrefix("x") || name.first?.isNumber == true {
            let digits = name.hasPrefix("#") ? String(name.dropFirst()) : name
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") { value = UInt32(digits.dropFirst(), radix: 16) }
            else { value = UInt32(digits) }
            guard let value, value >= 32 || value == 10, let scalar = Unicode.Scalar(value) else { return nil }
            return scalar
        }
        switch name {
        case "quot": return "\""
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "apos": return "'"
        case "nbsp": return " "
        default: return nil
        }
    }
}

/// Measures and wraps label text with Core Text, which is safe off the main actor. One measurer
/// belongs to one layout run, so its width cache needs no synchronization.
final class DiagramTextMeasurer {
    let font: DiagramFont
    let lineHeight: CGFloat
    private let regular: CTFont
    private let bold: CTFont
    private var regularWidths: [String: CGFloat] = [:]
    private var boldWidths: [String: CGFloat] = [:]

    init(font: DiagramFont) {
        self.font = font
        regular = font.ctFont()
        bold = font.ctFont(bold: true)
        lineHeight = Self.lineHeight(of: regular)
    }

    /// One formula for layout and drawing, so a measured label fills exactly the space drawn for it.
    static func lineHeight(of font: CTFont) -> CGFloat {
        ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)) + 2
    }

    func width(of text: String, bold isBold: Bool = false) -> CGFloat {
        if let cached = (isBold ? boldWidths : regularWidths)[text] { return cached }
        let width = Self.measure(text, font: isBold ? bold : regular)
        if isBold { boldWidths[text] = width } else { regularWidths[text] = width }
        return width
    }

    func size(of lines: [String], bold isBold: Bool = false) -> CGSize {
        guard !lines.isEmpty else { return .zero }
        return CGSize(width: lines.map { width(of: $0, bold: isBold) }.max() ?? 0,
                      height: lineHeight * CGFloat(lines.count))
    }

    /// Greedy word wrapping; a word wider than the limit is split between characters.
    func wrap(_ lines: [String], maximumWidth: CGFloat, bold isBold: Bool = false) -> [String] {
        var wrapped: [String] = []
        for line in lines {
            guard width(of: line, bold: isBold) > maximumWidth else { wrapped.append(line); continue }
            var current = ""
            for word in line.split(separator: " ", omittingEmptySubsequences: true).map(String.init) {
                let candidate = current.isEmpty ? word : current + " " + word
                if width(of: candidate, bold: isBold) <= maximumWidth { current = candidate; continue }
                if !current.isEmpty { wrapped.append(current); current = "" }
                if width(of: word, bold: isBold) <= maximumWidth { current = word; continue }
                for character in word {
                    let next = current + String(character)
                    if width(of: next, bold: isBold) > maximumWidth, !current.isEmpty {
                        wrapped.append(current)
                        current = String(character)
                    } else { current = next }
                }
            }
            if !current.isEmpty { wrapped.append(current) }
        }
        return Array(wrapped.prefix(DiagramLimits.maximumLabelLines * 2))
    }

    private static func measure(_ text: String, font: CTFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attributes = [kCTFontAttributeName: font] as CFDictionary
        guard let attributed = CFAttributedStringCreate(nil, text as CFString, attributes) else { return 0 }
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
