import Foundation
import PreviewContracts

/// The Invisibles preview mode: the safe text with every hidden character replaced by a visible,
/// technical marker, so a banner finding such as "Invisible zero-width characters: 214" can be
/// located. It is derived from the already concealed text, never from source bytes, and it never
/// replaces Source: Source copy and find keep the exact safe characters.
///
/// Markers use the spans of `HiddenCharacters.spans(in:)`, the same scan the findings use, so the
/// banner and the markers always agree. Notation is technical and not localized, like code
/// points: `⟨U+202E RLO⟩`, one marker per scalar, with the standard Unicode abbreviation when
/// one is established. A run of Unicode Tag characters collapses to one `⟨TAG ×N⟩` marker that
/// states only the count: their code points would reveal the message that the findings banner
/// shows privacy-filtered.
///
/// Line separators are never replaced and markers never contain a line break, so the derived text
/// has exactly the logical lines of the safe text, and gutter numbers and finding lines still match.
struct SafeInvisibleText: Equatable, Sendable {
    /// Hidden scalars (tags included) above which the mode is not offered.
    static let maximumHiddenScalars = 100_000
    /// UTF-8 size of the derived text above which the mode is not offered.
    static let maximumUTF8Bytes = 4 * 1_024 * 1_024
    /// Findings that make the mode worth offering. Deriving availability from findings avoids a
    /// scan on every clean preview. Mixed-script, comment and agent-instruction findings do not
    /// concern invisible characters.
    static let relevantFindingKinds: Set<PreviewFindingKind> = [
        .hiddenBidirectionalControls, .hiddenZeroWidth, .hiddenUnicodeTags,
        .hiddenVariationSelectors, .hiddenPrivateUse
    ]

    /// Safe text with markers in place of hidden characters.
    let text: String
    /// UTF-16 ranges of the markers in `text`, ascending, for styling.
    let markerRanges: [NSRange]

    /// Derives the mode for a presentation, or nil when its findings report no hidden characters
    /// or the bounds make the mode unavailable.
    static func make(for presentation: TextPresentation) -> Self? {
        guard presentation.findings.contains(where: { relevantFindingKinds.contains($0.kind) }) else { return nil }
        return derive(from: presentation.text)
    }

    /// Replaces each hidden span of `safeText`. Returns nil, never a truncated result, when there
    /// are more than `maximumHiddenScalars` hidden scalars, the derived text would exceed
    /// `maximumUTF8Bytes`, or the scan's spans are not ordered and within the text.
    static func derive(from safeText: String, maximumHiddenScalars: Int = Self.maximumHiddenScalars,
                       maximumUTF8Bytes: Int = Self.maximumUTF8Bytes) -> Self? {
        derive(from: safeText, spans: HiddenCharacters.spans(in: safeText),
               maximumHiddenScalars: maximumHiddenScalars, maximumUTF8Bytes: maximumUTF8Bytes)
    }

    /// As `derive(from:)` for spans the caller already holds. They must be ascending, non-empty,
    /// non-overlapping and start on scalar boundaries; otherwise the result is nil.
    static func derive(from safeText: String, spans: [HiddenCharacterSpan],
                       maximumHiddenScalars: Int = Self.maximumHiddenScalars,
                       maximumUTF8Bytes: Int = Self.maximumUTF8Bytes) -> Self? {
        let hiddenTotal = spans.reduce(0) { $0 + $1.scalarCount }
        guard hiddenTotal <= maximumHiddenScalars else { return nil }
        guard !spans.isEmpty else { return Self(text: safeText, markerRanges: []) }

        let scalars = Array(safeText.unicodeScalars)
        var output = String.UnicodeScalarView()
        var markerRanges: [NSRange] = []
        var outputUTF16 = 0
        var index = 0
        var offset = 0
        var hiddenSeen = 0

        func copy(_ scalar: Unicode.Scalar) {
            output.append(scalar)
            outputUTF16 += scalar.utf16.count
        }
        func mark(_ marker: String) {
            let length = marker.utf16.count
            markerRanges.append(NSRange(location: outputUTF16, length: length))
            output.append(contentsOf: marker.unicodeScalars)
            outputUTF16 += length
        }

        for span in spans {
            let range = span.utf16Range
            guard !range.isEmpty, range.lowerBound >= offset else { return nil }
            while offset < range.lowerBound {
                guard index < scalars.count else { return nil }
                copy(scalars[index])
                offset += scalars[index].utf16.count
                index += 1
            }
            // A span must start on a scalar boundary.
            guard offset == range.lowerBound else { return nil }
            var tags = 0
            while offset < range.upperBound {
                guard index < scalars.count else { return nil }
                let scalar = scalars[index]
                offset += scalar.utf16.count
                index += 1
                hiddenSeen += 1
                guard hiddenSeen <= maximumHiddenScalars else { return nil }
                if isLineSeparator(scalar) { copy(scalar) }
                else if span.kind == .tag { tags += 1 }
                else { mark(marker(for: scalar)) }
            }
            guard offset == range.upperBound else { return nil }
            if tags > 0 { mark(tagMarker(count: tags)) }
        }
        while index < scalars.count { copy(scalars[index]); index += 1 }

        let derived = String(output)
        guard derived.utf8.count <= maximumUTF8Bytes else { return nil }
        return Self(text: derived, markerRanges: markerRanges)
    }

    // MARK: Marker notation

    /// `⟨U+202E RLO⟩`: the code point, then the standard abbreviation when one exists.
    static func marker(for scalar: Unicode.Scalar) -> String {
        let codePoint = "U+" + hexadecimal(scalar.value)
        guard let name = abbreviation(for: scalar.value) else { return open + codePoint + close }
        return open + codePoint + " " + name + close
    }

    /// One marker for a whole run, stating only how many tag characters are hidden.
    static func tagMarker(count: Int) -> String { open + "TAG \u{00D7}" + String(count) + close }

    private static let open = "\u{27E8}"
    private static let close = "\u{27E9}"

    private static func abbreviation(for value: UInt32) -> String? {
        switch value {
        case 0xFE00...0xFE0F: "VS\(value - 0xFE00 + 1)"
        case 0xE0100...0xE01EF: "VS\(value - 0xE0100 + 17)"
        default: abbreviations[value]
        }
    }

    /// Unicode NameAliases abbreviations for the characters the scan reports. Others show the
    /// code point alone.
    private static let abbreviations: [UInt32: String] = [
        0x061C: "ALM", 0x00AD: "SHY", 0x034F: "CGJ",
        0x200B: "ZWSP", 0x200C: "ZWNJ", 0x200D: "ZWJ", 0x200E: "LRM", 0x200F: "RLM",
        0x202A: "LRE", 0x202B: "RLE", 0x202C: "PDF", 0x202D: "LRO", 0x202E: "RLO",
        0x2060: "WJ", 0x2066: "LRI", 0x2067: "RLI", 0x2068: "FSI", 0x2069: "PDI",
        0xFEFF: "ZWNBSP"
    ]

    private static func hexadecimal(_ value: UInt32) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }

    /// Mirrors `LogicalLines`: these scalars are never replaced, so line structure is unchanged.
    private static func isLineSeparator(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 10, 13, 0x85, 0x2028, 0x2029: true
        default: false
        }
    }
}
