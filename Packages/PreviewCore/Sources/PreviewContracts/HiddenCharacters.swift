import Foundation

/// Characters that change what text says or how it reads without being visible. The hidden-content
/// scan (findings) and the renderer's Invisibles mode both use `HiddenCharacters.spans`, so the
/// banner and the markers always agree. Characters that are expected in their context are skipped:
/// emoji joiners and selectors, joiners inside scripts that need them (Devanagari, Bengali, Arabic…),
/// subdivision-flag tag sequences, Mongolian and ideographic variation sequences and direction marks
/// in lines that contain right-to-left letters. An isolated Braille blank stays ordinary spacing;
/// adjacent runs of two or more are reported.
public enum HiddenCharacterClass: Sendable, CaseIterable {
    /// Embeddings, overrides, isolates and stray direction marks (Trojan Source, CVE-2021-42574).
    case bidirectionalControl
    /// Zero-width and other invisible formatting characters.
    case zeroWidth
    /// Unicode Tag characters, which can encode an invisible ASCII message ("ASCII smuggling").
    case tag
    /// Variation selectors outside an emoji, standardized or ideographic variation sequence.
    case variationSelector
    /// Private-use code points, often icon-font glyphs.
    case privateUse
}

/// A run of adjacent hidden characters of one class.
public struct HiddenCharacterSpan: Equatable, Sendable {
    public let kind: HiddenCharacterClass
    /// UTF-16 offsets in the scanned text.
    public let utf16Range: Range<Int>
    public let scalarCount: Int
    public init(kind: HiddenCharacterClass, utf16Range: Range<Int>, scalarCount: Int) {
        self.kind = kind; self.utf16Range = utf16Range; self.scalarCount = scalarCount
    }
}

public enum HiddenCharacters {
    /// Scalar membership without text-context exemptions. Filename risks retain direction marks
    /// even when the name contains right-to-left letters; `spans` decides those marks in context.
    public static func isBidirectionalControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: true
        default: false
        }
    }

    /// Returns hidden runs in text order. Text that is entirely ASCII returns at once: none of these
    /// characters is ASCII. Renderers call this on already bounded safe text.
    public static func spans(in text: String) -> [HiddenCharacterSpan] { spans(in: text, checkpoint: {}) }

    /// As `spans(in:)`, calling `checkpoint` every 4,096 scalars so request owners keep their deadline.
    public static func spans(in text: String, checkpoint: () throws -> Void) rethrows -> [HiddenCharacterSpan] {
        guard try mayContainHiddenCharacters(text, checkpoint: checkpoint) else { return [] }
        let scalars = Array(text.unicodeScalars)
        var spans: [HiddenCharacterSpan] = []
        // Direction marks are fine in a line that holds right-to-left letters; decide at the line's end.
        var pendingMarks: [HiddenCharacterSpan] = []
        var lineHasRightToLeft = false
        // Spans before this index belong to finished lines and are already in text order.
        var lineFirstSpan = 0
        var offset = 0
        var index = 0
        func append(_ kind: HiddenCharacterClass, _ range: Range<Int>, scalars count: Int) {
            if let last = spans.last, last.kind == kind, last.utf16Range.upperBound == range.lowerBound, kind != .bidirectionalControl {
                spans[spans.count - 1] = HiddenCharacterSpan(kind: kind, utf16Range: last.utf16Range.lowerBound..<range.upperBound,
                                                             scalarCount: last.scalarCount + count)
            } else {
                spans.append(HiddenCharacterSpan(kind: kind, utf16Range: range, scalarCount: count))
            }
        }
        func endLine() {
            // Only this line's spans can be out of order, and only when marks were added to them.
            if !lineHasRightToLeft, !pendingMarks.isEmpty {
                spans.append(contentsOf: pendingMarks)
                spans[lineFirstSpan...].sort { $0.utf16Range.lowerBound < $1.utf16Range.lowerBound }
            }
            pendingMarks.removeAll(keepingCapacity: true)
            lineHasRightToLeft = false
            lineFirstSpan = spans.count
        }
        while index < scalars.count {
            if index.isMultiple(of: 4096) { try checkpoint() }
            let scalar = scalars[index]
            let value = scalar.value
            // Most scalars are ASCII, which is never hidden and never right to left; only line ends matter.
            if value < 0x80 {
                if value == 10 || value == 13 { endLine() }
                offset += 1
                index += 1
                continue
            }
            let width = scalar.utf16.count
            let previous = index > 0 ? scalars[index - 1] : nil
            let next = index + 1 < scalars.count ? scalars[index + 1] : nil
            if isLineBreak(value) { endLine() }
            else if isRightToLeftLetter(scalar) { lineHasRightToLeft = true }

            if value == 0x1F3F4, let end = flagTagSequenceEnd(scalars, from: index + 1) {
                // A subdivision flag such as England: black flag, tag letters, cancel tag.
                for skipped in scalars[index..<end] { offset += skipped.utf16.count }
                index = end
                continue
            }
            if isVariationSelector(value) {
                let runEnd = variationRunEnd(scalars, from: index)
                let runWidth = scalars[index..<runEnd].reduce(0) { $0 + $1.utf16.count }
                if runEnd - index > 1 || !isExpectedSelector(scalar, after: previous) {
                    append(.variationSelector, offset..<(offset + runWidth), scalars: runEnd - index)
                }
                offset += runWidth
                index = runEnd
                continue
            }
            if let kind = classify(scalar, previous: previous, next: next) {
                let range = offset..<(offset + width)
                if kind == .bidirectionalControl, isDirectionMark(value) {
                    pendingMarks.append(HiddenCharacterSpan(kind: kind, utf16Range: range, scalarCount: 1))
                } else {
                    append(kind, range, scalars: 1)
                }
            }
            offset += width
            index += 1
        }
        endLine()
        return spans
    }

    // MARK: Classification

    private static func classify(_ scalar: Unicode.Scalar, previous: Unicode.Scalar?, next: Unicode.Scalar?) -> HiddenCharacterClass? {
        if isBidirectionalControl(scalar) { return .bidirectionalControl }
        let value = scalar.value
        switch value {
        case 0x200D:
            if isEmojiJoinable(previous) && isEmojiJoinable(next) { return nil }
            return joinsScript(previous) || joinsScript(next) ? nil : .zeroWidth
        case 0x200C:
            return joinsScript(previous) || joinsScript(next) ? nil : .zeroWidth
        case 0x200B, 0x2060...0x2064, 0x206A...0x206F, 0xFEFF, 0x180E, 0x00AD, 0x034F, 0x115F, 0x1160, 0x3164, 0xFFA0, 0x17B4, 0x17B5:
            return .zeroWidth
        case 0xFFF9...0xFFFB, 0x1D173...0x1D17A, 0x13430...0x1343F:
            return .zeroWidth
        case 0x2800:
            return previous?.value == 0x2800 || next?.value == 0x2800 ? .zeroWidth : nil
        case 0xE0000...0xE007F:
            return .tag
        case 0xE000...0xF8FF, 0xF0000...0xFFFFD, 0x100000...0x10FFFD:
            return .privateUse
        default:
            return nil
        }
    }

    private static func isDirectionMark(_ value: UInt32) -> Bool { value == 0x200E || value == 0x200F || value == 0x061C }

    private static func isLineBreak(_ value: UInt32) -> Bool {
        value == 10 || value == 13 || value == 0x85 || value == 0x2028 || value == 0x2029
    }

    /// Letters of the right-to-left scripts: Hebrew, Arabic, Syriac, Thaana, N'Ko, Samaritan, Mandaic and
    /// the supplementary RTL blocks. Only letters count, because only strong right-to-left text makes a
    /// direction mark expected. Format characters (U+061C ARABIC LETTER MARK, U+070F SYRIAC ABBREVIATION
    /// MARK), combining marks and digits lie in the same blocks but are not letters, so a line holding
    /// only those still reports its marks.
    private static func isRightToLeftLetter(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        guard (0x0590...0x08FF).contains(value) || (0xFB1D...0xFDFF).contains(value) || (0xFE70...0xFEFE).contains(value)
            || (0x10800...0x10FFF).contains(value) || (0x1E800...0x1EFFF).contains(value) else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
        default: return false
        }
    }

    /// Scripts in which ZWJ and ZWNJ select letter forms: Arabic family, Indic, Tibetan,
    /// Myanmar, Khmer, Mongolian and Brahmic supplements.
    private static func joinsScript(_ scalar: Unicode.Scalar?) -> Bool {
        guard let value = scalar?.value else { return false }
        return (0x0600...0x08FF).contains(value) || (0x0900...0x0DFF).contains(value) || (0x0F00...0x0FFF).contains(value)
            || (0x1000...0x109F).contains(value) || (0x1780...0x18AF).contains(value) || (0xA8E0...0xA8FF).contains(value)
            || (0xFB50...0xFDFF).contains(value) || (0xFE70...0xFEFE).contains(value) || (0x11000...0x111FF).contains(value)
    }

    /// Emoji, emoji modifiers and the emoji presentation selector may surround a ZWJ in an emoji sequence.
    private static func isEmojiJoinable(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        return scalar.value == 0xFE0F || (scalar.properties.isEmoji && scalar.value > 0x7F) || scalar.properties.isEmojiModifier
    }

    /// One selector is expected after a base it can modify. Runs of selectors are never expected:
    /// they are how variation-selector encodings (GlassWorm) carry data.
    private static func isExpectedSelector(_ selector: Unicode.Scalar, after base: Unicode.Scalar?) -> Bool {
        guard let base, !base.properties.isWhitespace, !isLineBreak(base.value) else { return false }
        let value = selector.value
        if (0x180B...0x180D).contains(value) || value == 0x180F {
            return (0x1820...0x18AA).contains(base.value) && base.properties.generalCategory == .otherLetter
        }
        if value == 0xFE0E || value == 0xFE0F { return base.properties.isEmoji }
        if (0xFE00...0xFE0D).contains(value) { return base.value > 0x7F }
        // Ideographic variation sequences follow CJK ideographs.
        let ideograph = base.value
        return (0x3400...0x4DBF).contains(ideograph) || (0x4E00...0x9FFF).contains(ideograph)
            || (0xF900...0xFAFF).contains(ideograph) || (0x20000...0x3134F).contains(ideograph)
    }

    private static func isVariationSelector(_ value: UInt32) -> Bool {
        (0x180B...0x180D).contains(value) || value == 0x180F
            || (0xFE00...0xFE0F).contains(value) || (0xE0100...0xE01EF).contains(value)
    }

    private static func variationRunEnd(_ scalars: [Unicode.Scalar], from start: Int) -> Int {
        var end = start
        while end < scalars.count, isVariationSelector(scalars[end].value) {
            end += 1
        }
        return end
    }

    /// Index after a valid flag tag sequence (tag letters or digits, then CANCEL TAG), or nil.
    private static func flagTagSequenceEnd(_ scalars: [Unicode.Scalar], from start: Int) -> Int? {
        var index = start
        while index < scalars.count, index - start < 32,
              (0xE0030...0xE0039).contains(scalars[index].value) || (0xE0061...0xE007A).contains(scalars[index].value) {
            index += 1
        }
        guard index > start, index < scalars.count, scalars[index].value == 0xE007F else { return nil }
        return index + 1
    }

    /// A cheap test on UTF-8 bytes that never misses a character `classify` or the variation-selector
    /// logic can report, so ordinary prose (ASCII, accented Latin, Cyrillic, CJK, emoji) skips the
    /// scalar scan. Each case names the code points it guards; it may over-report, never under-report.
    /// It calls `checkpoint` every 8,192 bytes, as the scalar scan does every 4,096 scalars.
    private static func mayContainHiddenCharacters(_ text: String, checkpoint: () throws -> Void) rethrows -> Bool {
        try text.utf8.withContiguousStorageIfAvailable { try bytesMayContainHiddenCharacters($0, checkpoint: checkpoint) }
            ?? !text.utf8.allSatisfy { $0 < 0x80 }
    }

    private static func bytesMayContainHiddenCharacters(_ bytes: UnsafeBufferPointer<UInt8>, checkpoint: () throws -> Void) rethrows -> Bool {
        let count = bytes.count
        var index = 0
        var blockEnd = 0
        while index < count {
            if index >= blockEnd {
                try checkpoint()
                blockEnd = index + 8192
            }
            let lead = bytes[index]
            index += 1
            // ASCII and continuation bytes: nothing hidden starts here.
            if lead < 0xC2 { continue }
            if lead < 0xE0 {
                // Two-byte sequences: only three code points matter, so most of Latin, Greek and Cyrillic stops here.
                guard lead == 0xC2 || lead == 0xCD || lead == 0xD8, index < count else { continue }
                let second = bytes[index]
                if (lead == 0xC2 && second == 0xAD)                         // U+00AD soft hyphen
                    || (lead == 0xCD && second == 0x8F)                     // U+034F combining grapheme joiner
                    || (lead == 0xD8 && second == 0x9C) { return true }     // U+061C arabic letter mark
                continue
            }
            let second: UInt8 = index < count ? bytes[index] : 0
            let third: UInt8 = index + 1 < count ? bytes[index + 1] : 0
            switch lead {
            case 0xE1: if second == 0x85 || second == 0x9E || second == 0xA0 { return true } // 115F 1160 17B4 17B5 180B-180F
            case 0xE2:
                // U+200B-200F, U+202A-202E, U+2060-206F: invisible formatting and direction controls.
                if second == 0x80, (0x8B...0x8F).contains(third) || (0xAA...0xAE).contains(third) { return true }
                if second == 0x81, (0xA0...0xAF).contains(third) { return true }
                if second == 0xA0, third == 0x80 { return true }             // U+2800 Braille blank; scalar scan checks its run
            case 0xE3: if second == 0x85 { return true }                     // U+3164 hangul filler
            case 0xEE: return true                                           // U+E000-EFFF private use
            case 0xEF:
                // U+F000-F8FF private use, U+FE00-FE0F selectors, U+FEFF, U+FFA0 filler, U+FFF9-FFFB annotations.
                if second <= 0xA3 || second == 0xB8 || second == 0xBB || (second == 0xBE && third >= 0xA0) { return true }
                if second == 0xBF, (0xB9...0xBB).contains(third) { return true }
            case 0xF0:
                let fourth: UInt8 = index + 2 < count ? bytes[index + 2] : 0
                if second == 0x93, third == 0x90, (0xB0...0xBF).contains(fourth) { return true } // U+13430-1343F Egyptian controls
                if second == 0x9D, third == 0x85, (0xB3...0xBA).contains(fourth) { return true } // U+1D173-1D17A musical controls
            case 0xF3, 0xF4: return true                                     // tags, selector supplement, private use planes
            default: break
            }
        }
        return false
    }
}
