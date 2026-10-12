import Foundation

/// Finds words that read as one script but mix in letters of another: `pаypal` with a Cyrillic а,
/// `Αpple` with a Greek capital alpha. These are the homoglyph spoofs behind look-alike package names,
/// identifiers and domains.
///
/// A word is a run of letters, combining marks, digits and `_`. It is flagged only when it holds Latin
/// letters and Cyrillic or Greek letters **and** the mix is a plausible spoof:
///
/// - **A.** a Cyrillic or Greek letter in the word is a known Latin look-alike (table below), or
/// - **B.** the word is otherwise Cyrillic or Greek (at least three such letters, more than the Latin
///   ones) and every Latin letter in it resembles a letter of that script.
///
/// Honest mixed words stay unflagged: `10μs`, `Δt` and `πr²` hold no look-alike letter and are too short
/// for B, and prose that is wholly Russian, Greek or Latin holds one script. Letters of other scripts
/// (CJK, Hebrew, Arabic…) end a word; they cannot spoof Latin, and skipping them keeps the pass cheap.
/// Known limits: Greek-letter variables written next to Latin ones (`ρmax`) are look-alikes by this
/// rule and are flagged; whole-script confusables (a word made only of Cyrillic а е о р с) and
/// Armenian, Cherokee or fullwidth look-alikes are not detected.
///
/// The pass reads UTF-8 bytes once with a table lookup per scalar, calling `onToken` with the UTF-8
/// offset of each flagged word, in text order.
enum MixedScriptDetector {
    static func scan(_ bytes: UnsafeBufferPointer<UInt8>, checkpoint: () throws -> Void,
                     onToken: (_ utf8Offset: Int) -> Void) throws {
        let count = bytes.count
        try classTable.withUnsafeBufferPointer { classes in
            var index = 0
            var tokenStart = 0
            var bits: UInt8 = 0
            var nextCheckpoint = checkpointInterval
            while index < count {
                if index >= nextCheckpoint {
                    try checkpoint()
                    nextCheckpoint = index + checkpointInterval
                }
                let scalarStart = index
                let scalarClass = nextClass(bytes, &index, classes)
                if scalarClass & Class.member != 0 {
                    if bits == 0 { tokenStart = scalarStart }
                    bits |= scalarClass
                } else if bits != 0 {
                    if isSpoof(bits: bits, bytes, tokenStart..<scalarStart, classes) { onToken(tokenStart) }
                    bits = 0
                }
            }
            if bits != 0, isSpoof(bits: bits, bytes, tokenStart..<count, classes) { onToken(tokenStart) }
        }
    }

    private static let checkpointInterval = 16_384

    // MARK: Decision

    /// `bits` is the union of the classes of a word's scalars.
    private static func isSpoof(bits: UInt8, _ bytes: UnsafeBufferPointer<UInt8>, _ word: Range<Int>,
                                _ classes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard bits & Class.latin != 0, bits & (Class.cyrillic | Class.greek) != 0 else { return false }
        if bits & Class.foreignLookalike != 0 { return true }
        // Rule B needs counts, so it rereads the word; only words that already mix scripts get here.
        var latin = 0
        var foreign = 0
        var latinResemblesCyrillic = true
        var latinResemblesGreek = true
        var index = word.lowerBound
        while index < word.upperBound {
            let scalarClass = nextClass(bytes, &index, classes)
            if scalarClass & Class.latin != 0 {
                latin += 1
                latinResemblesCyrillic = latinResemblesCyrillic && scalarClass & Class.latinResemblesCyrillic != 0
                latinResemblesGreek = latinResemblesGreek && scalarClass & Class.latinResemblesGreek != 0
            } else if scalarClass & (Class.cyrillic | Class.greek) != 0 {
                foreign += 1
            }
        }
        guard foreign >= 3, foreign > latin else { return false }
        let hasCyrillic = bits & Class.cyrillic != 0
        let hasGreek = bits & Class.greek != 0
        return (hasCyrillic && !hasGreek && latinResemblesCyrillic) || (hasGreek && !hasCyrillic && latinResemblesGreek)
    }

    // MARK: Classes

    /// Bit flags of one scalar. Zero ends a word.
    private enum Class {
        /// Letters, combining marks, decimal digits and `_`: part of a word.
        static let member: UInt8 = 0x01
        static let latin: UInt8 = 0x02
        static let cyrillic: UInt8 = 0x04
        static let greek: UInt8 = 0x08
        /// A Cyrillic or Greek letter that looks like a Latin one.
        static let foreignLookalike: UInt8 = 0x10
        /// A Latin letter that some Cyrillic (or Greek) letter looks like.
        static let latinResemblesCyrillic: UInt8 = 0x20
        static let latinResemblesGreek: UInt8 = 0x40
    }

    /// Decodes the scalar at `index` (valid UTF-8, as every Swift string is) and advances past it.
    @inline(__always)
    private static func nextClass(_ bytes: UnsafeBufferPointer<UInt8>, _ index: inout Int,
                                  _ classes: UnsafeBufferPointer<UInt8>) -> UInt8 {
        let lead = bytes[index]
        if lead < 0x80 {
            index += 1
            return classes[Int(lead)]
        }
        if lead < 0xE0 {
            let value = Int(lead & 0x1F) << 6 | Int(bytes[index + 1] & 0x3F)
            index += 2
            return value < classes.count ? classes[value] : 0
        }
        if lead < 0xF0 {
            let value = Int(lead & 0x0F) << 12 | Int(bytes[index + 1] & 0x3F) << 6 | Int(bytes[index + 2] & 0x3F)
            index += 3
            // Latin Extended Additional and Greek Extended hold whole letters; other scripts end a word.
            if (0x1E00...0x1EFF).contains(value) { return Class.member | Class.latin }
            if (0x1F00...0x1FFF).contains(value) { return Class.member | Class.greek }
            return 0
        }
        index += 4
        return 0
    }

    // MARK: Table

    /// Classes for U+0000...U+052F: ASCII, Latin-1, Latin Extended, IPA, combining marks, Greek and Cyrillic.
    private static let classTable: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 0x530)
        var letters = Set<Int>()
        for value in 0..<table.count {
            guard let scalar = Unicode.Scalar(UInt32(value)) else { continue }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
                table[value] = Class.member
                letters.insert(value)
            case .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber:
                table[value] = Class.member
            default: break
            }
        }
        table[0x5F] = Class.member
        // Latin script: ASCII letters, the ordinal indicators, Latin-1 and Latin Extended-A/B, IPA.
        for value in letters where (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value) || value == 0xAA || value == 0xBA
            || (0xC0...0x2AF).contains(value) {
            table[value] |= Class.latin
        }
        for value in letters where (0x370...0x3FF).contains(value) { table[value] |= Class.greek }
        for value in letters where (0x400...0x52F).contains(value) { table[value] |= Class.cyrillic }
        for (value, latin) in cyrillicLookalikes {
            table[Int(value)] |= Class.foreignLookalike
            markResemblance(&table, latin, Class.latinResemblesCyrillic)
        }
        for (value, latin) in greekLookalikes {
            table[Int(value)] |= Class.foreignLookalike
            markResemblance(&table, latin, Class.latinResemblesGreek)
        }
        return table
    }()

    private static func markResemblance(_ table: inout [UInt8], _ latin: Unicode.Scalar, _ flag: UInt8) {
        let letter = Int(latin.value)
        table[letter] |= flag
        // Look-alike pairs are matched by letter, whatever its case.
        table[letter ^ 0x20] |= flag
    }

    /// Cyrillic letters that look like a Latin letter in common fonts, with the letter they imitate.
    /// Small on purpose: only glyphs a reader cannot tell apart at a glance.
    private static let cyrillicLookalikes: [(UInt32, Unicode.Scalar)] = [
        (0x0430, "a"), (0x0432, "b"), (0x0435, "e"), (0x043A, "k"), (0x043C, "m"), (0x043D, "h"), (0x043E, "o"),
        (0x0440, "p"), (0x0441, "c"), (0x0442, "t"), (0x0443, "y"), (0x0445, "x"), (0x0455, "s"), (0x0456, "i"),
        (0x0458, "j"), (0x0501, "d"), (0x051B, "q"), (0x051D, "w"), (0x04AF, "y"), (0x04BB, "h"),
        (0x0410, "A"), (0x0412, "B"), (0x0415, "E"), (0x041A, "K"), (0x041C, "M"), (0x041D, "H"), (0x041E, "O"),
        (0x0420, "P"), (0x0421, "C"), (0x0422, "T"), (0x0423, "Y"), (0x0425, "X"), (0x0405, "S"), (0x0406, "I"),
        (0x0408, "J")
    ]

    /// Greek letters that look like a Latin letter: omicron, alpha, nu, rho, tau, upsilon, iota, kappa and
    /// the capitals that are drawn exactly like Latin ones.
    private static let greekLookalikes: [(UInt32, Unicode.Scalar)] = [
        (0x03BF, "o"), (0x03B1, "a"), (0x03BD, "v"), (0x03C1, "p"), (0x03C4, "t"), (0x03C5, "u"), (0x03B9, "i"),
        (0x03BA, "k"),
        (0x0391, "A"), (0x0392, "B"), (0x0395, "E"), (0x0396, "Z"), (0x0397, "H"), (0x0399, "I"), (0x039A, "K"),
        (0x039C, "M"), (0x039D, "N"), (0x039F, "O"), (0x03A1, "P"), (0x03A4, "T"), (0x03A5, "Y"), (0x03A7, "X")
    ]
}
