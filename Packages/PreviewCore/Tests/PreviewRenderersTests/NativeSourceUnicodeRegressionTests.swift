import AppKit
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Exact native source Unicode", .serialized)
@MainActor
struct NativeSourceUnicodeRegressionTests {
    enum Surface: CaseIterable, Sendable {
        case source, deferredSource, outline
    }

    @Test(arguments: Surface.allCases)
    func canonicallyEquivalentReplacementPreservesItsExactCodeUnits(surface: Surface) throws {
        let composedValue = "caf\u{00e9}"
        let decomposedValue = "cafe\u{0301}"
        let composed = "{\"\(composedValue)\":\"\(composedValue)\"}"
        let decomposed = "{\"\(decomposedValue)\":\"\(decomposedValue)\"}"
        #expect(composed == decomposed)
        #expect(Array(composed.utf16) != Array(decomposed.utf16))
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.display(.ready(presentation(composed)))
        if surface != .source { try selectMode(1, in: view) }
        view.display(.ready(presentation(decomposed)), resetsContentState: surface == .source)

        if surface == .outline {
            let scroll = view.outlineView
            let outline = try #require(scroll.documentView as? NSOutlineView)
            let item = try #require(outline.item(atRow: 1))
            for column in outline.tableColumns {
                let field = try #require(scroll.outlineView(outline, viewFor: column, item: item) as? NSTextField)
                #expect(Array(field.stringValue.utf16) == Array(decomposedValue.utf16))
            }
        } else {
            if surface == .deferredSource { try selectMode(0, in: view) }
            let text = try #require(view.scrollView.documentView as? NSTextView)
            #expect(Array(text.string.utf16) == Array(decomposed.utf16))
            #expect(text.textStorage?.length == decomposed.utf16.count)
        }
    }

    private func presentation(_ text: String) -> TextPresentation {
        // Source metadata can stay equal while concealment changes the safe spelling.
        // It describes the original file, rather than the UTF-8 size of safe text.
        .init(formatID: .json, text: text, lineCount: 1, byteCount: 128,
              encoding: .utf8, redactionCount: 0, syntax: .json)
    }

    private func selectMode(_ index: Int, in view: NativePreviewView) throws {
        let control = view.modeControl
        #expect(control.segmentCount > index)
        control.selectedSegment = index
        #expect(control.sendAction(control.action, to: control.target))
    }
}
