import Foundation

/// Paragraph direction by the first strong character, the rule of the Unicode Bidirectional
/// Algorithm (UAX #9, rules P2 and P3). Leading neutrals such as list markers, digits,
/// punctuation and symbols are skipped, so an Arabic or Hebrew list item resolves right-to-left.
enum MarkupDirection {
    /// A paragraph is scanned for at most this many scalars; longer neutral prefixes stay left-to-right.
    static let maximumScan = 256

    static func isRightToLeft<Scalars: Sequence>(_ scalars: Scalars) -> Bool where Scalars.Element == Unicode.Scalar {
        var scanned = 0
        for scalar in scalars {
            scanned += 1
            if scanned > maximumScan { return false }
            if let rightToLeft = strongDirection(of: scalar) { return rightToLeft }
        }
        return false
    }

    static func isRightToLeft(_ text: String) -> Bool { isRightToLeft(text.unicodeScalars) }

    /// `true` for a strong right-to-left character, `false` for a strong left-to-right one and
    /// `nil` for neutral and weak characters (digits, punctuation, symbols, marks, spaces).
    static func strongDirection(of scalar: Unicode.Scalar) -> Bool? {
        switch scalar.value {
        // Explicit marks: right-to-left mark, embedding and isolate initiators.
        case 0x200F, 0x202B, 0x202E, 0x2067: return true
        case 0x200E, 0x202A, 0x202D, 0x2066: return false
        // Hebrew, Arabic, Syriac, Arabic Supplement, Thaana, NKo, Samaritan, Mandaic, Syriac Supplement,
        // Arabic Extended-A and the Hebrew/Arabic presentation forms.
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return isLetter(scalar) ? true : nil
        // Right-to-left scripts in the supplementary planes (Phoenician through Adlam).
        case 0x10800...0x10FFF, 0x1E800...0x1EFFF: return isLetter(scalar) ? true : nil
        default: return isLetter(scalar) ? false : nil
        }
    }

    /// Letters are strong; digits (including Arabic-Indic digits), marks, punctuation and symbols are weak or neutral.
    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: true
        default: false
        }
    }
}
