import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private func hidden(_ kind: PreviewFindingKind = .hiddenZeroWidth) -> [PreviewFinding] {
    PreviewFindings.normalized([PreviewFinding(kind: kind, count: 1, lines: [1])])
}

private func presentation(_ text: String, format: FormatID = .plainText, syntax: TextSyntax = .plain,
                          findings: [PreviewFinding]? = nil) -> TextPresentation {
    TextPresentation(formatID: format, text: text, lineCount: 1, byteCount: text.utf8.count, encoding: .utf8,
                     redactionCount: 0, syntax: syntax, findings: findings ?? hidden())
}

/// Tag characters spelling `message`: the invisible "ASCII smuggling" encoding.
private func tags(_ message: String) -> String {
    var view = String.UnicodeScalarView()
    for scalar in message.unicodeScalars { view.append(Unicode.Scalar(0xE0000 + scalar.value)!) }
    return String(view)
}

private func derived(_ text: String) throws -> SafeInvisibleText {
    try #require(SafeInvisibleText.derive(from: text))
}

private func lineStarts(_ text: String) -> Int { LogicalLines.starts(in: text).starts.count }

@Suite("Invisibles marker text", .serialized)
struct InvisiblesMarkerTextTests {
    @Test func bidirectionalControlsUseStandardAbbreviations() throws {
        let controls: [(UInt32, String)] = [
            (0x202A, "LRE"), (0x202B, "RLE"), (0x202C, "PDF"), (0x202D, "LRO"), (0x202E, "RLO"),
            (0x2066, "LRI"), (0x2067, "RLI"), (0x2068, "FSI"), (0x2069, "PDI"), (0x200E, "LRM"), (0x200F, "RLM")
        ]
        for (value, name) in controls {
            let scalar = try #require(Unicode.Scalar(value))
            let result = try derived("a\(scalar)b")
            let hex = String(value, radix: 16, uppercase: true)
            let padded = String(repeating: "0", count: 4 - hex.count) + hex
            #expect(result.text == "a\u{27E8}U+\(padded) \(name)\u{27E9}b", "\(name)")
            #expect(result.markerRanges.count == 1)
        }
        // ALM counts as an Arabic letter in the scan, so no text reports it alone; its notation is still defined.
        #expect(SafeInvisibleText.marker(for: "\u{061C}") == "\u{27E8}U+061C ALM\u{27E9}")
        let trojan = try derived("if (admin\u{202E} \u{2066}) {\u{2069} \u{2066}")
        #expect(trojan.text == "if (admin\u{27E8}U+202E RLO\u{27E9} \u{27E8}U+2066 LRI\u{27E9}) {\u{27E8}U+2069 PDI\u{27E9} \u{27E8}U+2066 LRI\u{27E9}")
    }

    @Test func zeroWidthCharactersShowOneMarkerPerScalar() throws {
        #expect(try derived("pass\u{200B}word").text == "pass\u{27E8}U+200B ZWSP\u{27E9}word")
        #expect(try derived("a\u{200D}b").text == "a\u{27E8}U+200D ZWJ\u{27E9}b")
        #expect(try derived("a\u{200C}b").text == "a\u{27E8}U+200C ZWNJ\u{27E9}b")
        let run = try derived("x\u{2060}\u{FEFF}\u{00AD}\u{034F}y")
        #expect(run.text == "x\u{27E8}U+2060 WJ\u{27E9}\u{27E8}U+FEFF ZWNBSP\u{27E9}\u{27E8}U+00AD SHY\u{27E9}\u{27E8}U+034F CGJ\u{27E9}y")
        #expect(run.markerRanges.count == 4)
        // Characters without an established abbreviation show the code point alone.
        #expect(try derived("a\u{2061}\u{3164}b").text == "a\u{27E8}U+2061\u{27E9}\u{27E8}U+3164\u{27E9}b")
        // A run of the same character is still one marker each.
        #expect(try derived("\u{200B}\u{200B}\u{200B}").markerRanges.count == 3)
    }

    @Test func variationSelectorsAreNumbered() throws {
        #expect(try derived("a\u{FE01}").text == "a\u{27E8}U+FE01 VS2\u{27E9}")
        #expect(try derived("a\u{FE0F}\u{FE0F}").text == "a\u{27E8}U+FE0F VS16\u{27E9}\u{27E8}U+FE0F VS16\u{27E9}")
        #expect(try derived("x\u{E0100}").text == "x\u{27E8}U+E0100 VS17\u{27E9}")
        #expect(try derived("x\u{E01EF}").text == "x\u{27E8}U+E01EF VS256\u{27E9}")
    }

    @Test func privateUseShowsOnlyTheCodePoint() throws {
        #expect(try derived("icon\u{E000}").text == "icon\u{27E8}U+E000\u{27E9}")
        #expect(try derived("a\u{F0000}b").text == "a\u{27E8}U+F0000\u{27E9}b")
        #expect(try derived("a\u{10FFFD}b").text == "a\u{27E8}U+10FFFD\u{27E9}b")
    }

    @Test func aTagRunIsOneMarkerThatNeverLeaksCodePointsOrLetters() throws {
        let message = "ignore previous instructions"
        let result = try derived("a" + tags(message) + "b")
        #expect(result.text == "a\u{27E8}TAG \u{00D7}\(message.count)\u{27E9}b")
        #expect(result.markerRanges.count == 1)
        #expect(!result.text.contains("U+"))
        #expect(!result.text.contains("E00"))
        #expect(!result.text.contains("ignore"))
        #expect(result.text.unicodeScalars.allSatisfy { !(0xE0000...0xE007F).contains($0.value) })
        // Separate runs stay separate; the marker states only each run's count.
        let two = try derived(tags("ab") + "\u{200B}" + tags("xyz"))
        #expect(two.text == "\u{27E8}TAG \u{00D7}2\u{27E9}\u{27E8}U+200B ZWSP\u{27E9}\u{27E8}TAG \u{00D7}3\u{27E9}")
        // A subdivision flag is not hidden content and is left alone.
        let flag = "\u{1F3F4}" + tags("gbeng") + "\u{E007F}"
        let untouched = try derived(flag)
        #expect(untouched.text.utf8.elementsEqual(flag.utf8))
        #expect(untouched.markerRanges.isEmpty)
    }

    @Test func markerRangesIndexTheMarkersInTheDerivedText() throws {
        let result = try derived("a\u{200B}\u{1F600}b\u{202E}" + tags("hi") + "c\u{E000}")
        let nsText = result.text as NSString
        let substrings = result.markerRanges.map { nsText.substring(with: $0) }
        #expect(substrings == ["\u{27E8}U+200B ZWSP\u{27E9}", "\u{27E8}U+202E RLO\u{27E9}", "\u{27E8}TAG \u{00D7}2\u{27E9}", "\u{27E8}U+E000\u{27E9}"])
        #expect(zip(result.markerRanges, result.markerRanges.dropFirst()).allSatisfy { NSMaxRange($0) <= $1.location })
        #expect(result.markerRanges.allSatisfy { NSMaxRange($0) <= nsText.length })
    }

    @Test func expectedContextsAndCleanTextAreLeftExactly() throws {
        for text in ["plain ascii\n", "שלום\u{200F}abc", "👨‍👩‍👧", "नमस्ते क्‍ष", "caf\u{00E9} e\u{0301}"] {
            let result = try derived(text)
            #expect(result.text.utf8.elementsEqual(text.utf8), "\(text)")
            #expect(result.markerRanges.isEmpty)
        }
    }

    @Test func markersContainNoLineBreaksAndLineStructureIsIdentical() throws {
        let samples = [
            "a\r\nb\u{200B}\r\nc",
            "a\u{2028}b\u{200B}\u{2028}c\u{2029}",
            "x\u{200B}\ny\u{202E}\nz\u{200B}\u{200B}",
            "a\u{200B}\rb\u{202E}\n",
            "a\r\u{200B}\nb",
            "\u{200B}\n\u{202E}\n",
            "tag" + tags("line") + "\n" + tags("two") + "\r\nend\u{85}\u{E000}\u{85}"
        ]
        for text in samples {
            let result = try derived(text)
            #expect(lineStarts(result.text) == lineStarts(text), "\(text.debugDescription)")
            for range in result.markerRanges {
                let marker = (result.text as NSString).substring(with: range)
                #expect(marker.unicodeScalars.allSatisfy { ![10, 13, 0x85, 0x2028, 0x2029].contains($0.value) })
            }
            // Every marker sits on the logical line of the character it replaces.
            let expected = LogicalLines.lineNumbers(forUTF16Offsets: markerOffsets(in: text), in: text)
            let actual = LogicalLines.lineNumbers(forUTF16Offsets: result.markerRanges.map(\.location), in: result.text)
            #expect(actual == expected, "\(text.debugDescription)")
        }
    }

    @Test func lineSeparatorsInsideASpanAreNeverReplaced() throws {
        let text = "a\u{200B}\nb"
        let span = HiddenCharacterSpan(kind: .zeroWidth, utf16Range: 1..<3, scalarCount: 2)
        let result = try #require(SafeInvisibleText.derive(from: text, spans: [span]))
        #expect(result.text == "a\u{27E8}U+200B ZWSP\u{27E9}\nb")
        #expect(result.markerRanges.count == 1)
    }

    @Test func malformedSpansMakeTheModeUnavailableInsteadOfCrashing() {
        let text = "a\u{200B}b"
        let good = HiddenCharacterSpan(kind: .zeroWidth, utf16Range: 1..<2, scalarCount: 1)
        #expect(SafeInvisibleText.derive(from: text, spans: [good]) != nil)
        let outside = HiddenCharacterSpan(kind: .zeroWidth, utf16Range: 5..<9, scalarCount: 1)
        let overlapping = HiddenCharacterSpan(kind: .zeroWidth, utf16Range: 1..<3, scalarCount: 2)
        let empty = HiddenCharacterSpan(kind: .zeroWidth, utf16Range: 1..<1, scalarCount: 0)
        #expect(SafeInvisibleText.derive(from: text, spans: [outside]) == nil)
        #expect(SafeInvisibleText.derive(from: text, spans: [good, good]) == nil)
        #expect(SafeInvisibleText.derive(from: text, spans: [overlapping, good]) == nil)
        #expect(SafeInvisibleText.derive(from: text, spans: [empty]) == nil)
    }

    @Test func boundsMakeTheModeUnavailableWithoutTruncating() throws {
        #expect(SafeInvisibleText.derive(from: String(repeating: "\u{200B}", count: 4), maximumHiddenScalars: 3) == nil)
        #expect(SafeInvisibleText.derive(from: String(repeating: "\u{200B}", count: 3), maximumHiddenScalars: 3)?.markerRanges.count == 3)
        // The documented limits.
        let atLimit = try derived(String(repeating: "\u{200B}", count: SafeInvisibleText.maximumHiddenScalars))
        #expect(atLimit.markerRanges.count == SafeInvisibleText.maximumHiddenScalars)
        #expect(SafeInvisibleText.derive(from: String(repeating: "\u{200B}", count: SafeInvisibleText.maximumHiddenScalars + 1)) == nil)
        // Tag characters count as hidden scalars even though they collapse into one marker.
        #expect(SafeInvisibleText.derive(from: String(repeating: "\u{E0041}", count: SafeInvisibleText.maximumHiddenScalars + 1)) == nil)
        // The derived UTF-8 size is bounded, not just the number of markers. Derived: 1,000 + 17 bytes.
        #expect(SafeInvisibleText.maximumUTF8Bytes == 4 * 1_024 * 1_024)
        let text = String(repeating: "a", count: 1_000) + "\u{200B}"
        #expect(SafeInvisibleText.derive(from: text, maximumUTF8Bytes: 1_016) == nil)
        #expect(SafeInvisibleText.derive(from: text, maximumUTF8Bytes: 1_017)?.text.utf8.count == 1_017)
    }

    @Test func availabilityFollowsOnlyTheHiddenCharacterFindings() {
        let text = "a\u{200B}b"
        #expect(SafeInvisibleText.make(for: presentation(text, findings: [])) == nil)
        for kind: PreviewFindingKind in [.secretAPIKey, .secretPrivateKey, .hiddenMixedScripts, .hiddenMarkdownComments,
                                        .hiddenAgentInstructions, .notebookOutOfOrder, .archiveUnsafePath] {
            #expect(SafeInvisibleText.make(for: presentation(text, findings: [PreviewFinding(kind: kind, count: 1)])) == nil, "\(kind)")
        }
        for kind in SafeInvisibleText.relevantFindingKinds {
            #expect(SafeInvisibleText.make(for: presentation(text, findings: hidden(kind))) != nil, "\(kind)")
        }
        #expect(SafeInvisibleText.relevantFindingKinds == [.hiddenBidirectionalControls, .hiddenZeroWidth, .hiddenUnicodeTags,
                                                          .hiddenVariationSelectors, .hiddenPrivateUse])
    }

    /// UTF-16 offsets of what the markers replace: each hidden scalar, but one per tag run.
    private func markerOffsets(in text: String) -> [Int] {
        var offsets: [Int] = []
        for span in HiddenCharacters.spans(in: text) {
            var offset = 0
            var previousWasTag = false
            for scalar in text.unicodeScalars {
                defer { offset += scalar.utf16.count }
                guard span.utf16Range.contains(offset), ![10, 13, 0x85, 0x2028, 0x2029].contains(scalar.value) else { continue }
                if span.kind == .tag {
                    if !previousWasTag { offsets.append(offset) }
                    previousWasTag = true
                } else { offsets.append(offset) }
            }
        }
        return offsets
    }
}

@Suite("Invisibles preview mode", .serialized)
@MainActor
struct InvisiblesModeTests {
    private let english = Locale(identifier: "en_US")
    private var invisiblesTitle: String { PreviewStrings.text(.previewModeInvisibles) }

    // MARK: Availability

    @Test func modeAppearsLastOnlyWithHiddenFindingsAndNeverFirst() throws {
        let text = "pass\u{200B}word\nsafe\n"
        let clean = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        clean.display(.ready(presentation(text, findings: [])), locale: english)
        #expect(try segmentTitles(clean).isEmpty)
        #expect(try modeControl(clean).isHidden)

        let secretOnly = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        secretOnly.display(.ready(presentation(text, findings: [PreviewFinding(kind: .secretAPIKey, count: 1)])), locale: english)
        #expect(try segmentTitles(secretOnly).isEmpty)

        for kind in SafeInvisibleText.relevantFindingKinds {
            let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
            view.display(.ready(presentation(text, findings: hidden(kind))), locale: english)
            let titles = try segmentTitles(view)
            #expect(titles == [PreviewStrings.text(.previewModeSource), invisiblesTitle], "\(kind)")
            #expect(try modeControl(view).selectedSegment == 0, "\(kind)")
            #expect(!(try modeControl(view).isHidden))
        }
    }

    @Test func modeCoexistsWithRenderedForMarkdown() throws {
        let text = "# Title\nhello\u{202E} world\n"
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.display(.ready(presentation(text, format: .markdown, syntax: .markdown,
                                         findings: hidden(.hiddenBidirectionalControls))), locale: english)
        #expect(try segmentTitles(view) == [PreviewStrings.text(.previewModeSource), PreviewStrings.text(.previewModeRendered),
                                            invisiblesTitle])
        // Markdown opens in Rendered (decision 015); Invisibles stays last and is never the initial mode.
        #expect(try modeControl(view).selectedSegment == 1)
        let modes = SafePreviewModes(presentation(text, format: .markdown, syntax: .markdown, findings: hidden()), locale: english)
        #expect(modes.available == [.source, .rendered, .invisibles])
        #expect(modes.initialMode(for: .markdown) == .rendered)
    }

    @Test func modeCoexistsWithTableForCSV() throws {
        let text = "name,note\nada,hi\u{200B}\nbob,ok\n"
        let value = presentation(text, format: .csv, syntax: .commaSeparated)
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.display(.ready(value), locale: english)
        let titles = try segmentTitles(view)
        #expect(titles == [PreviewStrings.text(.previewModeSource), PreviewStrings.text(.previewModeTable),
                           PreviewStrings.text(.previewModeProfile), invisiblesTitle])
        // The table stays the initial mode.
        #expect(try modeControl(view).selectedSegment == 1)
        let modes = SafePreviewModes(value, locale: english)
        #expect(modes.initialMode(for: .csv) == .table)
        #expect(modes.available.last == .invisibles)
    }

    @Test func modeCoexistsWithOutlineSummaryRecordsAndCues() {
        let json = #"{"a":"x\#u{200B}y"}"#
        let outline = SafePreviewModes(presentation(json, format: .json, syntax: .json), locale: english)
        #expect(outline.available == [.source, .outline, .invisibles])
        let records = SafePreviewModes(presentation(#"{"a":"x\#u{200B}y"}"# + "\n", format: .jsonLines, syntax: .json), locale: english)
        #expect(records.available == [.source, .records, .invisibles])
        let srt = "1\n00:00:01,000 --> 00:00:02,000\nhel\u{200B}lo\n"
        let cues = SafePreviewModes(presentation(srt, format: .subRip, syntax: .subRip), locale: english)
        #expect(cues.available.last == .invisibles)
        #expect(!cues.available.isEmpty && cues.available.first == .source)
    }

    @Test func boundsMakeTheModeUnavailableInTheModeList() {
        let big = String(repeating: "\u{200B}", count: SafeInvisibleText.maximumHiddenScalars + 1)
        let modes = SafePreviewModes(presentation(big), locale: english)
        #expect(modes.invisibles == nil)
        #expect(modes.available == [.source])
        #expect(SafePreviewModes(presentation("a\u{200B}b"), locale: english).available == [.source, .invisibles])
    }

    // MARK: Display

    @Test func invisiblesShowsMarkersAndKeepsTheLinesAndTheGutter() throws {
        let text = "one\u{200B}\r\ntwo\u{202E}\nthree" + tags("hidden") + "\u{2028}four\n"
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        view.display(.ready(presentation(text, findings: hidden())), typography: PreviewTypography(showsLineNumbers: true),
                     locale: english)
        try select(invisiblesTitle, in: view)
        view.layoutSubtreeIfNeeded()
        let (_, content, gutter) = try components(of: view)
        let expected = try derived(text)
        #expect(content.string == expected.text)
        #expect(content.string.contains("\u{27E8}U+200B ZWSP\u{27E9}"))
        #expect(content.string.contains("\u{27E8}TAG \u{00D7}6\u{27E9}"))
        #expect(!content.string.contains("hidden"))
        #expect(!gutter.isHidden)
        #expect(gutter.lineIndex.count == lineStarts(text))
        #expect(gutter.lineIndex.starts.count == 5)
        #expect(gutter.visibleLabels(in: content).map(\.number) == Array(1...5))
        #expect(content.isSelectable && !content.isEditable && content.usesFindBar)
        #expect(content.accessibilityLabel() == PreviewStrings.text(.selectableContent))
        #expect(content.accessibilityHelp() == PreviewStrings.text(.contentHelp))
        #expect(gutter.accessibilityLabel() == PreviewStrings.text(.lineNumbers))
    }

    @Test func sourceStaysExactlyTheSafeTextBeforeAndAfterVisitingInvisibles() throws {
        // A decomposed accent differs in code units from its canonical equivalent.
        let text = "cafe\u{0301}\u{200B}\u{202E}x\n"
        let value = presentation(text)
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.display(.ready(value), locale: english)
        let (_, content, _) = try components(of: view)
        #expect(Array(content.string.utf8) == Array(text.utf8))
        try select(invisiblesTitle, in: view)
        #expect(Array(content.string.utf8) != Array(text.utf8))
        #expect(content.string.contains("\u{27E8}U+202E RLO\u{27E9}"))
        try select(PreviewStrings.text(.previewModeSource), in: view)
        #expect(Array(content.string.utf8) == Array(text.utf8))
        #expect(content.textStorage?.length == text.utf16.count)
        // Restyling while in Source does not reintroduce markers.
        view.display(.ready(value), typography: .init(fontSize: 18), theme: .dark, locale: english)
        #expect(Array(content.string.utf8) == Array(text.utf8))
    }

    @Test func copyInSourceWritesTheExactSafeTextAndInvisiblesCopiesItsOwnText() throws {
        let text = "cafe\u{0301}\u{200B}\u{202E}x\n" + tags("p") + "end"
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.display(.ready(presentation(text)), locale: english)
        let (_, content, _) = try components(of: view)
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }

        func copyAll() -> String? {
            content.setSelectedRange(NSRange(location: 0, length: (content.string as NSString).length))
            pasteboard.clearContents()
            guard content.writeSelection(to: pasteboard, types: content.writablePasteboardTypes) else { return nil }
            return pasteboard.string(forType: .string)
        }
        #expect(copyAll().map { Array($0.utf8) } == Array(text.utf8))
        try select(invisiblesTitle, in: view)
        let expected = try derived(text)
        #expect(copyAll().map { Array($0.utf8) } == Array(expected.text.utf8))
        try select(PreviewStrings.text(.previewModeSource), in: view)
        #expect(copyAll().map { Array($0.utf8) } == Array(text.utf8))
    }

    @Test func switchingModesResetsSelectionLikeRendered() throws {
        let text = "line\u{200B}\n" + String(repeating: "safe line\n", count: 80)
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        view.display(.ready(presentation(text)), locale: english)
        view.layoutSubtreeIfNeeded()
        let (scroll, content, _) = try components(of: view)
        content.setSelectedRange(NSRange(location: 5, length: 4))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
        try select(invisiblesTitle, in: view)
        #expect(content.selectedRange() == NSRange(location: 0, length: 0))
        #expect(scroll.contentView.bounds.origin == .zero)
        content.setSelectedRange(NSRange(location: 3, length: 2))
        // Appearance-only changes keep the selection in the derived text.
        view.display(.ready(presentation(text)), typography: .init(fontSize: 16), theme: .dark, locale: english)
        #expect(content.selectedRange() == NSRange(location: 3, length: 2))
    }

    // MARK: Styling

    @Test func markersAreStyledDistinctlyAndStayStyledAcrossThemeAndColorChanges() throws {
        let text = "a\u{200B}b\u{202E}c" + tags("zz") + "d"
        let value = presentation(text)
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 700, height: 300))
        view.display(.ready(value), theme: .light, locale: english)
        try select(invisiblesTitle, in: view)
        let (_, content, _) = try components(of: view)
        let expected = try derived(text)
        let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let light = NativeTextPalette(theme: .light, isDark: false, increasedContrast: increased)
        let dark = NativeTextPalette(theme: .dark, isDark: true, increasedContrast: increased)

        func color(_ at: Int) -> NSColor? { content.textStorage?.attribute(.foregroundColor, at: at, effectiveRange: nil) as? NSColor }
        func underline(_ at: Int) -> Int? { content.textStorage?.attribute(.underlineStyle, at: at, effectiveRange: nil) as? Int }
        func font(_ at: Int) -> NSFont? { content.textStorage?.attribute(.font, at: at, effectiveRange: nil) as? NSFont }
        func check(_ palette: NativeTextPalette, usesColor: Bool, label: String) {
            #expect(content.string == expected.text, "\(label)")
            let style = PreviewSyntaxStyle(usesColor: usesColor)
            for range in expected.markerRanges {
                // Every unit of the marker, including its brackets.
                for position in [range.location, NSMaxRange(range) - 1] {
                    #expect(color(position) == palette.invisibleMarkerColor(style: style), "\(label)")
                    #expect(underline(position) == (usesColor ? nil : NSUnderlineStyle.single.rawValue), "\(label)")
                    let traits = font(position).map { NSFontManager.shared.traits(of: $0) } ?? []
                    #expect(traits.contains(.boldFontMask), "\(label)")
                }
            }
            // The text between markers keeps the body style.
            #expect(color(0) == palette.foreground, "\(label)")
            #expect(underline(0) == nil, "\(label)")
        }
        check(light, usesColor: true, label: "light")
        #expect(light.invisibleMarkerColor() != light.foreground)
        view.display(.ready(value), theme: .dark, locale: english)
        check(dark, usesColor: true, label: "dark")
        view.display(.ready(value), theme: .dark, syntaxStyle: .init(usesColor: false), locale: english)
        check(dark, usesColor: false, label: "dark without color")
        #expect(dark.invisibleMarkerColor(style: .init(usesColor: false)) == dark.foreground)
        view.display(.ready(value), typography: .init(fontSize: 22), theme: .light, locale: english)
        check(light, usesColor: true, label: "light after typography")
        view.viewDidChangeEffectiveAppearance()
        check(light, usesColor: true, label: "light after appearance")
    }

    @Test func markerColorKeepsReadableContrastInEveryTheme() throws {
        for theme in PreviewTheme.allCases {
            for dark in [false, true] {
                for increased in [false, true] {
                    let palette = NativeTextPalette(theme: theme, isDark: dark, increasedContrast: increased)
                    let minimum = theme == .highContrast || increased ? 7.0 : 4.5
                    #expect(try contrast(palette.invisibleMarkerColor(), palette.background) >= minimum,
                            "\(theme) dark=\(dark) increased=\(increased)")
                    #expect(try contrast(palette.invisibleMarkerColor(style: .init(usesColor: false)), palette.background) >= minimum)
                }
            }
        }
    }

    @Test func syntaxHighlightingSurvivesInInvisiblesWithoutColoringMarkersAsSource() throws {
        let text = "{\"k\":\"a\u{200B}b\"}"
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 700, height: 300))
        view.display(.ready(presentation(text, format: .plainText, syntax: .json)), theme: .light, locale: english)
        try select(invisiblesTitle, in: view)
        let (_, content, _) = try components(of: view)
        let expected = try derived(text)
        let marker = try #require(expected.markerRanges.first)
        let palette = NativeTextPalette(theme: .light, isDark: false,
                                        increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        let keyColor = content.textStorage?.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        #expect(keyColor == palette.color(for: .key))
        let markerColor = content.textStorage?.attribute(.foregroundColor, at: marker.location, effectiveRange: nil) as? NSColor
        #expect(markerColor == palette.invisibleMarkerColor())
    }

    // MARK: Generations

    @Test func aReplacementPresentationClearsTheOldDerivedText() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.display(.ready(presentation("alpha\u{200B}beta")), locale: english)
        try select(invisiblesTitle, in: view)
        let (_, content, _) = try components(of: view)
        #expect(content.string == "alpha\u{27E8}U+200B ZWSP\u{27E9}beta")

        // Another hidden-character file: the mode stays selected and shows only the new derived text.
        view.display(.ready(presentation("gamma\u{202E}delta")), locale: english)
        #expect(content.string == "gamma\u{27E8}U+202E RLO\u{27E9}delta")
        #expect(!content.string.contains("ZWSP"))
        #expect(!content.string.contains("alpha"))
        #expect(content.selectedRange() == NSRange(location: 0, length: 0))

        // The same text with the findings gone: Invisibles is unavailable, so the exact text returns.
        view.display(.ready(presentation("gamma\u{202E}delta", findings: [])), locale: english)
        #expect(content.string == "gamma\u{202E}delta")
        #expect(try segmentTitles(view).isEmpty)

        // A clean replacement and then a non-content outcome keep nothing.
        view.display(.ready(presentation("alpha\u{200B}beta")), locale: english)
        try select(invisiblesTitle, in: view)
        view.display(.ready(presentation("clean", findings: [])), locale: english, resetsContentState: true)
        #expect(content.string == "clean")
        view.display(.ready(presentation("alpha\u{200B}beta")), locale: english)
        try select(invisiblesTitle, in: view)
        for outcome: PreviewOutcome in [.disabledByUser(.plainText), .unavailable(.malformedDocument), .cancelled] {
            view.display(.ready(presentation("alpha\u{200B}beta")), locale: english)
            try select(invisiblesTitle, in: view)
            view.display(outcome, locale: english)
            #expect(!content.string.contains("\u{27E8}"), "\(outcome)")
            #expect(!content.string.contains("alpha"), "\(outcome)")
            #expect(try modeControl(view).isHidden)
        }
        view.display(.ready(presentation("alpha\u{200B}beta")), locale: english)
        try select(invisiblesTitle, in: view)
        view.showLoading()
        #expect(!content.string.contains("\u{27E8}"))
    }

    @Test func aDifferentFormatReturnsToItsInitialModeNotInvisibles() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.display(.ready(presentation("alpha\u{200B}beta")), locale: english)
        try select(invisiblesTitle, in: view)
        let csv = presentation("name,note\nada,hi\u{200B}\n", format: .csv, syntax: .commaSeparated)
        view.display(.ready(csv), locale: english)
        let control = try modeControl(view)
        #expect(try segmentTitles(view).last == invisiblesTitle)
        #expect(control.selectedSegment == 1)
    }

    // MARK: Helpers

    private func modeControl(_ view: NativePreviewView) throws -> NSSegmentedControl {
        view.modeControl
    }

    /// Titles of the visible mode segments; empty while the control is hidden (Source only).
    private func segmentTitles(_ view: NativePreviewView) throws -> [String] {
        let control = try modeControl(view)
        guard !control.isHidden else { return [] }
        return (0..<control.segmentCount).map { control.label(forSegment: $0) ?? "" }
    }

    private func select(_ title: String, in view: NativePreviewView) throws {
        let control = try modeControl(view)
        let index = try #require((0..<control.segmentCount).first { control.label(forSegment: $0) == title })
        control.selectedSegment = index
        #expect(control.sendAction(control.action, to: control.target))
    }

    private func components(of view: NativePreviewView) throws -> (NSScrollView, NSTextView, LogicalLineNumberGutter) {
        let scroll = view.scrollView
        return (scroll, try #require(scroll.documentView as? NSTextView), view.lineNumberGutter)
    }

    private func contrast(_ first: NSColor, _ second: NSColor) throws -> Double {
        func luminance(_ color: NSColor) throws -> Double {
            let value = try #require(color.usingColorSpace(.sRGB))
            func linear(_ component: CGFloat) -> Double {
                let d = Double(component)
                return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(value.redComponent) + 0.7152 * linear(value.greenComponent) + 0.0722 * linear(value.blueComponent)
        }
        let a = try luminance(first), b = try luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
