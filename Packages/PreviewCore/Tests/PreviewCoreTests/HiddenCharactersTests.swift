import Foundation
import Testing
import PreviewContracts

private func kinds(_ text: String) -> [HiddenCharacterClass] {
    HiddenCharacters.spans(in: text).map(\.kind)
}

@Suite("Hidden character classification")
struct HiddenCharactersTests {
    @Test func asciiTextHasNoHiddenCharacters() {
        #expect(HiddenCharacters.spans(in: "let access = \"user\" // ok\n").isEmpty)
        #expect(HiddenCharacters.spans(in: "").isEmpty)
    }

    @Test func trojanSourceControlsAreFoundWithExactUTF16Ranges() {
        // An override and an isolate pair, as in CVE-2021-42574 examples.
        let text = "if (isAdmin) {\u{202E} } \u{2066}// check\u{2069}"
        let spans = HiddenCharacters.spans(in: text)
        #expect(spans.map(\.kind) == [.bidirectionalControl, .bidirectionalControl, .bidirectionalControl])
        let units = Array(text.utf16)
        for span in spans {
            #expect(span.utf16Range.count == 1)
            #expect([0x202E, 0x2066, 0x2069].contains(units[span.utf16Range.lowerBound]))
        }
    }

    @Test func directionMarksAreExpectedOnlyInLinesWithRightToLeftLetters() {
        #expect(kinds("price\u{200F}: 10") == [.bidirectionalControl])
        #expect(kinds("שלום\u{200F} world").isEmpty)
        #expect(kinds("שלום\nprice\u{200E}") == [.bidirectionalControl])
        #expect(kinds("price\u{200E}\nשלום").count == 1)
    }

    @Test func theArabicLetterMarkIsReportedUnlessTheLineHoldsRightToLeftLetters() {
        // The mark is a format character, not a letter: it must not make its own line right to left.
        #expect(kinds("price\u{061C}: 10") == [.bidirectionalControl])
        #expect(kinds("\u{061C}") == [.bidirectionalControl])
        // Inside a real Arabic line, and next to Hebrew letters, direction marks are expected.
        #expect(HiddenCharacters.spans(in: "مرحبا\u{061C} بالعالم").isEmpty)
        #expect(HiddenCharacters.spans(in: "שלום\u{061C} world").isEmpty)
        // Digits, combining marks and Hebrew points are in the same blocks but are not strong letters.
        #expect(kinds("\u{0661}\u{0662}\u{061C} 12") == [.bidirectionalControl])
        #expect(kinds("a\u{0651}\u{200F}") == [.bidirectionalControl])
        #expect(kinds("\u{05B0}\u{200E}") == [.bidirectionalControl])
        // A later letter in the line still makes the earlier mark expected.
        #expect(HiddenCharacters.spans(in: "price\u{061C} \u{0628}").isEmpty)
    }

    @Test func marksAndOtherRunsStayInTextOrderWithinAndAcrossLines() {
        let text = "a\u{200E}b\u{200B}c\u{200F}\nשלום\u{200F}\ny\u{200E}z\u{2060}"
        let spans = HiddenCharacters.spans(in: text)
        #expect(spans.map(\.kind) == [.bidirectionalControl, .zeroWidth, .bidirectionalControl, .bidirectionalControl, .zeroWidth])
        #expect(spans.map(\.utf16Range.lowerBound) == spans.map(\.utf16Range.lowerBound).sorted())
        #expect(spans.count == 5)
    }

    @Test func everyScalarIsReportedExactlyWhenItIsInvisibleOrDirectional() {
        // Independent of the implementation: what the documentation promises, scalar by scalar. This also
        // proves the byte-level shortcut for ordinary text never skips a hidden character.
        let hidden: [ClosedRange<UInt32>] = [
            0x00AD...0x00AD, 0x034F...0x034F, 0x061C...0x061C, 0x115F...0x1160, 0x17B4...0x17B5, 0x180B...0x180F,
            0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2064, 0x2066...0x206F, 0x3164...0x3164, 0xE000...0xF8FF,
            0xFE00...0xFE0F, 0xFEFF...0xFEFF, 0xFFA0...0xFFA0, 0xFFF9...0xFFFB, 0x13430...0x1343F,
            0x1D173...0x1D17A, 0xE0000...0xE007F, 0xE0100...0xE01EF,
            0xF0000...0xFFFFD, 0x100000...0x10FFFD
        ]
        var checked = 0
        var value: UInt32 = 0
        while value <= 0x10FFFF {
            defer {
                // Plane 3 to plane 13 hold only unassigned code points; sample them.
                value += (0x30000...0xDFFFF).contains(value) ? 251 : 1
            }
            guard let scalar = Unicode.Scalar(value) else { continue }
            // 0x200C and 0x200D are letters-joiners and report only between Latin letters, as here.
            let expected = hidden.contains { $0.contains(value) }
            let found = !HiddenCharacters.spans(in: "a\(scalar)b").isEmpty
            if found != expected { Issue.record("U+\(String(value, radix: 16, uppercase: true)): expected \(expected)") }
            checked += 1
        }
        #expect(checked > 250_000)
    }

    @Test func manySpansOnManyLinesStayLinear() {
        // A sort of the whole result at every line end would make this quadratic.
        let line = "a\u{200B}b\u{202E}c\u{E0A0}d\u{200F}\n"
        let spans = HiddenCharacters.spans(in: String(repeating: line, count: 20_000))
        #expect(spans.count == 80_000)
        #expect(spans.map(\.utf16Range.lowerBound) == spans.map(\.utf16Range.lowerBound).sorted())
    }

    @Test func invisibleFormattingControlsInTheirWholeBlockAreReported() {
        let spans = HiddenCharacters.spans(in: "a\u{206A}\u{206B}\u{206C}\u{206D}\u{206E}\u{206F}b")
        #expect(spans.map(\.kind) == [.zeroWidth])
        #expect(spans.first?.scalarCount == 6)
    }

    @Test func zeroWidthCharactersAreFoundAndAdjacentOnesFormOneRun() {
        let spans = HiddenCharacters.spans(in: "pass\u{200B}\u{200B}\u{2060}word and\u{FEFF}more")
        #expect(spans.map(\.kind) == [.zeroWidth, .zeroWidth])
        #expect(spans.map(\.scalarCount) == [3, 1])
        #expect(kinds("soft\u{00AD}hyphen") == [.zeroWidth])
        #expect(kinds("a\u{200D}b") == [.zeroWidth])
        #expect(kinds("a\u{200C}b") == [.zeroWidth])
    }

    @Test func joinersThatShapeEmojiOrIndicAndArabicTextAreExpected() {
        // Family emoji, a woman technologist and a skin-tone sequence.
        #expect(HiddenCharacters.spans(in: "👨\u{200D}👩\u{200D}👧 👩🏽\u{200D}💻 🏳\u{FE0F}\u{200D}🌈").isEmpty)
        // Hindi and Bengali conjunct control, Persian half-space.
        #expect(HiddenCharacters.spans(in: "क्\u{200D}ष र्\u{200C}य ক্\u{200D}য মি\u{200C}").isEmpty)
        #expect(HiddenCharacters.spans(in: "می\u{200C}خواهم").isEmpty)
    }

    @Test func unicodeTagRunsAreOneSpanButSubdivisionFlagsAreExpected() {
        let smuggled = "Hello" + "ignore".unicodeScalars.map { String(Unicode.Scalar($0.value + 0xE0000)!) }.joined()
        let spans = HiddenCharacters.spans(in: smuggled)
        #expect(spans.map(\.kind) == [.tag])
        #expect(spans.first?.scalarCount == 6)
        #expect(spans.first?.utf16Range.count == 12)
        // England: black flag, g b e n g, cancel tag.
        let england = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        #expect(HiddenCharacters.spans(in: "Go \(england)!").isEmpty)
        // A flag sequence without its cancel tag is not a flag.
        #expect(kinds("\u{1F3F4}\u{E0067}\u{E0062}x") == [.tag])
    }

    @Test func variationSelectorsAreExpectedOnlyAfterBasesTheyModify() {
        #expect(HiddenCharacters.spans(in: "❤\u{FE0F} ☺\u{FE0E} 1\u{FE0F}\u{20E3}").isEmpty)
        // Ideographic variation sequence after a CJK ideograph.
        #expect(HiddenCharacters.spans(in: "葛\u{E0100}城").isEmpty)
        #expect(kinds("a\u{FE0F}") == [.variationSelector])
        #expect(kinds("x\u{E0100}") == [.variationSelector])
        #expect(kinds("\u{FE0F}start") == [.variationSelector])
        // A run carries data even after a valid base (GlassWorm-style encodings).
        let run = "❤" + String(repeating: "\u{FE01}\u{E0105}", count: 8)
        let spans = HiddenCharacters.spans(in: run)
        #expect(spans.map(\.kind) == [.variationSelector])
        #expect(spans.first?.scalarCount == 16)
    }

    @Test func privateUseCodePointsAreReported() {
        #expect(kinds("branch \u{E0A0} main") == [.privateUse])
        #expect(kinds("\u{F0001}") == [.privateUse])
    }

    @Test func checkpointRunsDuringLongScansAndCanStopThem() {
        struct Stop: Error {}
        let text = String(repeating: "é", count: 20_000)
        var calls = 0
        #expect(throws: Stop.self) {
            _ = try HiddenCharacters.spans(in: text) {
                calls += 1
                if calls == 3 { throw Stop() }
            }
        }
        #expect(calls == 3)
    }
}
