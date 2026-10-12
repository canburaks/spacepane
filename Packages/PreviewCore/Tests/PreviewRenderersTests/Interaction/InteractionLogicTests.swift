import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Interaction logic")
struct InteractionLogicTests {
    // MARK: Zoom

    @Test func zoomStepsStayInsideTheTypographyRange() {
        var zoom = PreviewZoom()
        let base = PreviewTypography(fontSize: 13)
        #expect(zoom.isDefault && zoom.applying(to: base) == base)
        let movedIn = zoom.zoomIn(from: base)
        #expect(movedIn && zoom.applying(to: base).fontSize == 14)
        let movedOut = zoom.zoomOut(from: base)
        #expect(movedOut && zoom.isDefault)
        // Many steps never leave 8...48, and the last step at a bound reports no change.
        var changed = true
        var steps = 0
        while changed && steps < 200 { changed = zoom.zoomIn(from: base); steps += 1 }
        #expect(zoom.applying(to: base).fontSize == PreviewTypography.fontSizeRange.upperBound)
        let pastTop = zoom.zoomIn(from: base)
        #expect(!pastTop)
        changed = true
        steps = 0
        while changed && steps < 200 { changed = zoom.zoomOut(from: base); steps += 1 }
        #expect(zoom.applying(to: base).fontSize == PreviewTypography.fontSizeRange.lowerBound)
        let pastBottom = zoom.zoomOut(from: base)
        #expect(!pastBottom)
        #expect(zoom.applying(to: base).isValid)
        zoom.reset()
        #expect(zoom.isDefault)
    }

    @Test func everyZoomStepMovesAtLeastOnePointAndZoomIsRelativeToTheSavedSize() {
        var zoom = PreviewZoom()
        var base = PreviewTypography(fontSize: 8)
        var previous = base.fontSize
        while zoom.zoomIn(from: base) {
            let size = zoom.applying(to: base).fontSize
            #expect(size >= previous + 1)
            previous = size
        }
        // The offset follows a later change of the saved size and is clamped again.
        base.fontSize = 40
        #expect(zoom.applying(to: base).fontSize == 48)
        base.fontSize = 10
        #expect(zoom.applying(to: base).isValid)
        #expect(zoom.scale(of: base) ?? 0 > 1)
    }

    @Test func anInvalidSavedSizeIsNeverZoomed() {
        var zoom = PreviewZoom()
        let invalid = PreviewTypography(fontSize: .nan)
        let moved = zoom.zoomIn(from: invalid)
        #expect(!moved)
        #expect(zoom.applying(to: invalid).fontSize.isNaN)
        #expect(zoom.scale(of: invalid) == nil)
    }

    // MARK: Paths

    @Test func pathsUseDotsForIdentifiersAndBracketsForIndexesAndOtherKeys() {
        func path(_ steps: [(String, String?)], documents: Bool = false) -> String {
            OutlinePath.make(steps: steps.map { OutlinePath.Step(name: $0.0, parentValue: $0.1) }, rootsAreDocuments: documents)
        }
        #expect(path([("$", nil)]) == "$")
        #expect(path([("$", nil), ("a", "{…}"), ("b", "{…}"), ("[2]", "[…]")]) == "$.a.b[2]")
        #expect(path([("$", nil), ("users", "{…}"), ("[1]", "[…]"), ("name", "{…}")]) == "$.users[1].name")
        #expect(path([("$", nil), ("my key", "{…}")]) == "$['my key']")
        #expect(path([("$", nil), ("a-b", "{…}"), ("9lives", "{…}"), ("", "{…}")]) == "$['a-b']['9lives']['']")
        #expect(path([("$", nil), ("it's", "{…}"), ("back\\slash", "{…}")]) == "$['it\\'s']['back\\\\slash']")
        #expect(path([("$", nil), ("line\nbreak", "{…}"), ("tab\t", "{…}"), ("\u{1}", "{…}")]) == "$['line\\nbreak']['tab\\t']['\\u0001']")
        #expect(path([("$", nil), ("日本語", "{…}")]) == "$['日本語']")
        // A key spelled like an index under an object is still a key.
        #expect(path([("$", nil), ("[0]", "{…}")]) == "$['[0]']")
        // Top-level rows other than `$` are the first keys, unless every row is its own document.
        #expect(path([("database", nil), ("host", "")]) == "$.database.host")
        #expect(path([("Record 3", nil), ("name", "{…}")], documents: true) == "$.name")
        #expect(path([("Record 3", nil)], documents: true) == "$")
    }

    // MARK: Go to Line

    @Test func lineNumbersAreWholePositiveNumbersInAnyScript() {
        #expect(GoToLine.lineNumber(from: "12") == 12)
        #expect(GoToLine.lineNumber(from: "  7\n") == 7)
        #expect(GoToLine.lineNumber(from: "٣") == 3)
        #expect(GoToLine.lineNumber(from: "১২") == 12)
        for rejected in ["", " ", "abc", "1.5", "-3", "+3", "1,000", "1 2", "0x10", "١٢a", String(repeating: "9", count: 40)] {
            #expect(GoToLine.lineNumber(from: rejected) == nil, "\(rejected)")
        }
    }

    @Test func resolvingALineSelectsItsTextWithoutTheSeparator() throws {
        let text = "alpha\r\nbeta\n\n😀 gamma\u{2028}last"
        let index = LogicalLineIndex(text)
        let ns = text as NSString
        func target(_ input: String) throws -> GoToLine.Target {
            try GoToLine.resolve(input, in: ns, index: index).get()
        }
        #expect(ns.substring(with: try target("1").range) == "alpha")
        #expect(ns.substring(with: try target("2").range) == "beta")
        #expect(try target("3").range.length == 0)
        #expect(ns.substring(with: try target("4").range) == "😀 gamma")
        #expect(ns.substring(with: try target("5").range) == "last")
        #expect(try target("5").lineCount == 5)
        for invalid in ["0", "6", "-1", "x", ""] {
            #expect(GoToLine.resolve(invalid, in: ns, index: index) == .failure(.outOfRange(lineCount: 5)))
        }
    }

    @Test func aTrailingSeparatorGivesAnEmptyFinalLineAndEmptyTextHasNone() throws {
        let text = "a\n" as NSString
        let index = LogicalLineIndex(text as String)
        #expect(try GoToLine.resolve("2", in: text, index: index).get().range == NSRange(location: 2, length: 0))
        #expect(GoToLine.resolve("1", in: "", index: LogicalLineIndex("")) == .failure(.noLines))
        // An index that no longer describes the text is never trusted.
        #expect(index.contentRange(ofLine: 0, in: "different length" as NSString) == nil)
    }

    // MARK: Shortcuts

    @Test func shortcutsMatchTheirKeysOnlyWithTheRightModifiers() {
        let command: NSEvent.ModifierFlags = .command
        let shifted: NSEvent.ModifierFlags = [.command, .shift]
        #expect(PreviewShortcut(characters: "l", modifiers: command) == .goToLine)
        #expect(PreviewShortcut(characters: "L", modifiers: command) == .goToLine)
        #expect(PreviewShortcut(characters: "c", modifiers: shifted) == .copyAll)
        #expect(PreviewShortcut(characters: "c", modifiers: command) == nil)
        #expect(PreviewShortcut(characters: "f", modifiers: command) == .find)
        #expect(PreviewShortcut(characters: "g", modifiers: command) == .findNext)
        #expect(PreviewShortcut(characters: "g", modifiers: shifted) == .findPrevious)
        for key in ["=", "+"] {
            #expect(PreviewShortcut(characters: key, modifiers: command) == .zoomIn)
            #expect(PreviewShortcut(characters: key, modifiers: shifted) == .zoomIn)
        }
        for key in ["-", "_"] {
            #expect(PreviewShortcut(characters: key, modifiers: command) == .zoomOut)
            #expect(PreviewShortcut(characters: key, modifiers: shifted) == .zoomOut)
        }
        #expect(PreviewShortcut(characters: "0", modifiers: command) == .zoomReset)
        // Plain keys, Option and Control combinations, and other Command keys are never ours.
        #expect(PreviewShortcut(characters: "l", modifiers: []) == nil)
        #expect(PreviewShortcut(characters: "l", modifiers: [.command, .option]) == nil)
        #expect(PreviewShortcut(characters: "l", modifiers: [.command, .control]) == nil)
        #expect(PreviewShortcut(characters: "+", modifiers: [.control]) == nil)
        #expect(PreviewShortcut(characters: "a", modifiers: command) == nil)
        #expect(PreviewShortcut(characters: "ll", modifiers: command) == nil)
        #expect(PreviewShortcut(characters: nil, modifiers: command) == nil)
        // The numeric-pad flag, caps lock and function flag do not change the meaning.
        #expect(PreviewShortcut(characters: "+", modifiers: [.command, .numericPad, .capsLock]) == .zoomIn)
    }

    // MARK: Filter query

    @Test func filterQueriesIgnoreCaseDiacriticsAndWidthAndNeverActAsPatterns() throws {
        let query = try #require(OutlineFilterQuery("  JOSÉ "))
        #expect(query.isContained(in: OutlineFilterQuery.fold("Dr. José Álvarez")))
        #expect(query.isContained(in: OutlineFilterQuery.fold("JOSE")))
        #expect(!query.isContained(in: OutlineFilterQuery.fold("Josh")))
        #expect(OutlineFilterQuery("   \n") == nil)
        let wide = try #require(OutlineFilterQuery("ＡＢＣ"))
        #expect(wide.isContained(in: OutlineFilterQuery.fold("xabcx")))
        let literal = try #require(OutlineFilterQuery(".*"))
        #expect(!literal.isContained(in: OutlineFilterQuery.fold("anything")))
        #expect(literal.isContained(in: OutlineFilterQuery.fold("a.*b")))
        // Searching reads a bounded prefix of one field, and the query itself is bounded.
        let long = String(repeating: "a", count: OutlineFilterQuery.searchedUnitsPerField) + "needle"
        let needle = try #require(OutlineFilterQuery("needle"))
        #expect(!needle.isContained(in: OutlineFilterQuery.fold(long)))
        let huge = try #require(OutlineFilterQuery(String(repeating: "x", count: 5_000)))
        #expect(huge.folded.utf16.count == OutlineFilterQuery.maximumQueryUnits)
    }
}
