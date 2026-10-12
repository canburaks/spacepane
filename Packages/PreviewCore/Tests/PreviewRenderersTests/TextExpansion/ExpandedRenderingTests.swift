import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Expanded native text rendering")
struct ExpandedRenderingTests {
    @Test func codeDecorationsRetainUnicodeRangesAndNeverChangeSafeText() {
        let source = "// 😀 comment\nlet password = ••••\nlet value = \"👩🏽‍💻\"\nreturn 42"
        let tokens = SourceSyntaxTokens.tokens(in: source, syntax: .sourceCode)
        let ns = source as NSString
        #expect(tokens.contains { $0.role == .keyword && ns.substring(with: $0.range) == "let" })
        #expect(tokens.contains { $0.role == .comment && ns.substring(with: $0.range) == "// 😀 comment" })
        #expect(tokens.contains { $0.role == .string && ns.substring(with: $0.range) == "\"👩🏽‍💻\"" })
        #expect(tokens.allSatisfy { NSMaxRange($0.range) <= ns.length })
        #expect(SourceSyntaxTokens.tokens(in: source, syntax: .sourceCode, maximumUTF16Units: 8).isEmpty)
        #expect(SourceSyntaxTokens.tokens(in: source, syntax: .sourceCode, maximumTokens: 2).isEmpty)
    }

    @Test func diffRolesDecorateLoadedLinesWithoutApplyingPatches() {
        let source = "--- a/file\n+++ b/file\n@@ -1 +1 @@\n-old\n+new\n unchanged"
        let roles = SourceSyntaxTokens.tokens(in: source, syntax: .diff).map(\.role)
        #expect(roles == [.deletion, .addition, .heading, .deletion, .addition])
    }

    @Test func nativeMarkdownSubsetRendersInertLinksImagesTablesAndCode() throws {
        let source = "# Heading\n**bold** and *italic* [link](javascript:inert)\n![alt](https://example.invalid/image.png)\n| A | B |\n| --- | --- |\n| one | two |\n```swift\nlet token = ••••\n```\n<script>literal</script>"
        let result = try #require(SafeMarkdownDocument.render(source))
        #expect(result.text.contains("Heading"))
        #expect(result.text.contains("bold and italic link (javascript:inert)"))
        #expect(result.text.contains("alt"))
        #expect(!result.text.contains("image.png"))
        #expect(result.text.contains("one\ttwo"))
        #expect(result.text.contains("let token = ••••"))
        #expect(result.text.contains("<script>literal</script>"))
        #expect(result.decorations.contains { $0.style == .heading(1) })
        #expect(result.decorations.allSatisfy { NSMaxRange($0.range) <= result.text.utf16.count })
        #expect(SafeMarkdownDocument.render(String(repeating: "x", count: 65), maximumUTF16Units: 64) == nil)
    }

    @Test func modesContainOnlySafeValuesAndRecordIssues() throws {
        let presentation = TextPresentation(formatID: .jsonLines, text: "{\"password\":••••}\n••••\n", lineCount: 3, byteCount: 32, encoding: .utf8, redactionCount: 2, syntax: .json, invalidRecordLines: [2])
        let modes = SafePreviewModes(presentation, locale: Locale(identifier: "en"))
        let records = try #require(modes.records)
        #expect(records.count == 2)
        #expect(records[0].children.first?.value == "••••")
        #expect(records[1].isIssue)
        #expect(records[1].value.contains("2"))
    }

    @Test func safeXMLOutlineCannotResolveEntityDeclarations() {
        #expect(SafeXMLDocument.nodes("<!DOCTYPE root [<!ENTITY x SYSTEM 'file:///tmp/inert'>]><root>&x;</root>") == nil)
        #expect(SafeXMLDocument.nodes("<root><password>••••</password></root>")?.first?.children.first?.value == "••••")
        let safeCommentSource = "<root><!--••••--><safe>visible</safe></root>"
        let presentation = TextPresentation(formatID: .xml, text: safeCommentSource, lineCount: 1,
                                            byteCount: 96, encoding: .utf8, redactionCount: 1, syntax: .xml)
        let modes = SafePreviewModes(presentation, locale: Locale(identifier: "en"))
        #expect(modes.available.contains(.source))
        #expect(modes.outline?.first?.children.first?.value == "visible")
        #expect(!modes.hasStructureFallback)
    }

    @Test func crossRecordConcealmentDeclinesRecordLabels() {
        let presentation = TextPresentation(formatID: .jsonLines, text: "{\"value\":\"••••\"}\n", lineCount: 2,
                                            byteCount: 128, encoding: .utf8, redactionCount: 1, syntax: .json,
                                            invalidRecordLines: [2], sourceRecordCount: 3)
        let modes = SafePreviewModes(presentation, locale: Locale(identifier: "en"))
        #expect(modes.records == nil)
        #expect(modes.hasStructureFallback)
    }

    @Test func generatedSchemaLabelsPreserveUserColumnNamesAndExactValues() throws {
        let source = #"{"pages":[{"table":"1000","loadedRows":1000,"rows":[{"table":{"value":"1000","truncated":false,"sourceType":"text"},"value":{"value":"true","truncated":false,"sourceType":"text"},"blob":{"blobBytes":4096}}]}]}"#
        let roots = try #require(SafeStructuredText.json(source))
        let localized = SafeSchemaLabels.localize(roots, formatID: .sqlite, locale: Locale(identifier: "de_DE"))
        let page = localized[0].children[0].children[0]
        #expect(page.children[0].value == "1000")
        #expect(page.children[1].value == "1.000")
        let row = page.children[2].children[0]
        #expect(row.children.map(\.name) == ["table", "value", "blob"])
        #expect(row.children[0].children[0].value == "1000")
        #expect(row.children[1].children[0].value == "true")
        #expect(row.children[2].children[0].name == PreviewStrings.text(.summaryBlobBytes))
        #expect(row.children[2].children[0].value == "4.096")
        let folderSource = #"{"archiveFormat":"directory","entries":[{"path":"directory","type":"directory"}]}"#
        let folderRoots = try #require(SafeStructuredText.json(folderSource))
        let folder = SafeSchemaLabels.localize(folderRoots, formatID: .folder, locale: Locale(identifier: "de_DE"))
        #expect(folder[0].children[0].value == PreviewStrings.text(.summaryKindDirectory))
        #expect(folder[0].children[1].children[0].children[0].value == "directory")
    }

    @Test @MainActor func nativeSourceModePreservesTextSelectionDuringSyntaxStyleUpdates() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let presentation = TextPresentation(formatID: .sourceCode, text: "let safe = \"😀\"\nreturn 42", lineCount: 2, byteCount: 28, encoding: .utf8, redactionCount: 0, syntax: .sourceCode)
        view.display(.ready(presentation))
        let textView = try #require(view.scrollView.documentView as? NSTextView)
        textView.setSelectedRange(NSRange(location: 4, length: 4))
        view.display(.ready(presentation), syntaxStyle: .init(usesColor: false, boldRoles: [.keyword]))
        #expect(textView.string == presentation.text)
        #expect(textView.selectedRange() == NSRange(location: 4, length: 4))
        view.display(.disabledByUser(.sourceCode))
        #expect(!textView.string.contains("let safe"))
    }
}
