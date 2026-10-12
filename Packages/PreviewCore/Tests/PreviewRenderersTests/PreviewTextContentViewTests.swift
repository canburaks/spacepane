import AppKit
import Testing
import PreviewContracts
@testable import PreviewRenderers

@MainActor
private final class TextCharacterEditRecorder: NSObject, @preconcurrency NSTextStorageDelegate {
    private(set) var characterEdits = 0

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        if editedMask.contains(.editedCharacters) { characterEdits += 1 }
    }
}

@Suite("Preview text content ownership", .serialized)
@MainActor
struct PreviewTextContentViewTests {
    private func presentation(_ text: String) -> TextPresentation {
        .init(formatID: .plainText, text: text, lineCount: 1, byteCount: 128,
              encoding: .utf8, redactionCount: 0)
    }

    @Test func unchangedSafeTextKeepsTheTextKitStackAndSelectionWithoutCharacterEdits() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let safe = "safe cafe\u{0301} text"
        view.display(.ready(presentation(safe)))
        let storage = try #require(view.textView.textStorage)
        let manager = try #require(view.textView.layoutManager)
        let container = try #require(view.textView.textContainer)
        let scroll = view.scrollView
        let gutter = view.lineNumberGutter
        let selection = NSRange(location: 5, length: 5)
        view.textView.setSelectedRange(selection)
        let recorder = TextCharacterEditRecorder()
        let previousDelegate = storage.delegate
        storage.delegate = recorder
        defer { storage.delegate = previousDelegate }

        view.display(.ready(presentation(safe)))
        view.display(.ready(presentation(safe)), typography: .init(fontSize: 18, showsLineNumbers: true), theme: .dark)
        #expect(recorder.characterEdits == 0)
        #expect(view.textView.textStorage === storage && view.textView.layoutManager === manager)
        #expect(view.textView.textContainer === container && view.scrollView === scroll && view.lineNumberGutter === gutter)
        #expect(view.textView.textLayoutManager == nil && scroll.documentView === view.textView)
        #expect(view.textView.selectedRange() == selection)
        #expect(view.textView.string.utf16.elementsEqual(safe.utf16))
        #expect(gutter.lineIndex.utf16Length == safe.utf16.count)
    }

    @Test func canonicallyEquivalentReplacementWithEqualMetadataStillEditsTheDisplayedCharacters() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let composed = "safe caf\u{00e9} text"
        let decomposed = "safe cafe\u{0301} text"
        #expect(composed == decomposed)
        view.display(.ready(presentation(composed)))
        let storage = try #require(view.textView.textStorage)
        let recorder = TextCharacterEditRecorder()
        let previousDelegate = storage.delegate
        storage.delegate = recorder
        defer { storage.delegate = previousDelegate }

        view.display(.ready(presentation(decomposed)))
        #expect(recorder.characterEdits > 0)
        #expect(view.textView.textStorage === storage)
        #expect(storage.string.utf16.elementsEqual(decomposed.utf16))
        #expect(view.lineNumberGutter.lineIndex.utf16Length == decomposed.utf16.count)
    }
}
