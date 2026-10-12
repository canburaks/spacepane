import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

// Decision 027, Q-07 and Q-14: what the hosting view says. These tests go through `NativePreviewView.display` and
// therefore need the host to take its document notices from
// `MarkupRendering.notices(for:document:mode:locale:)` (instead of appending the offline sentence to every Rendered
// view and also asking `PresentationNotices`), and to pass the whole presentation to `SafeMarkdownDocument.render`.

private let english = Locale(identifier: "en")

@Suite("Document notices in the native preview", .serialized)
@MainActor
struct DocumentsNoticesHostTests {
    private func host() -> NativePreviewView { NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 400)) }

    private func status(_ view: NativePreviewView) -> String {
        view.displayedStatus
    }

    private func displayedText(_ view: NativePreviewView) -> String {
        (view.scrollView.documentView as? NSTextView)?.string ?? ""
    }

    private func occurrences(of needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }

    private func select(_ mode: NativePreviewMode, in view: NativePreviewView) throws {
        let control = view.modeControl
        let label = PreviewStrings.text(mode.title)
        let index = try #require((0..<control.segmentCount).first { control.label(forSegment: $0) == label })
        control.selectedSegment = index
        #expect(control.sendAction(control.action, to: control.target))
    }

    @Test func formulasAreNotedOnceAndOnlyInRendered() throws {
        let view = host()
        view.display(.ready(presentation(.latex, text: "$x^2$ and more", syntax: .latex)), locale: english)
        let notice = PreviewStrings.text(.markupMathNotice)
        #expect(occurrences(of: notice, in: status(view)) == 1)
        try select(.source, in: view)
        #expect(occurrences(of: notice, in: status(view)) == 0)
        try select(.rendered, in: view)
        #expect(occurrences(of: notice, in: status(view)) == 1)
    }

    @Test func theOfflineSentenceAppearsOnlyWhenSomethingWasLeftOutAndNeverInSource() throws {
        let nothing = host()
        nothing.display(.ready(presentation(.markdown, text: "# Title\n\nText with [a link](https://example.invalid).", syntax: .markdown)), locale: english)
        let oldSentence = PreviewStrings.text(.previewMarkdownLocalOnly)
        #expect(!status(nothing).contains(oldSentence))

        let images = host()
        images.display(.ready(presentation(.markdown, text: "# Title\n\n![Plan](plan.png) and ![Logo](https://example.invalid/l.png)", syntax: .markdown)), locale: english)
        let line = PreviewStrings.format(.documentOmittedImages, arguments: ["2"], locale: english)
        #expect(occurrences(of: line, in: status(images)) == 1)
        #expect(!status(images).contains(oldSentence))
        try select(.source, in: images)
        #expect(!status(images).contains(line))
    }

    @Test func theCitationCaveatAppearsOnceInRenderedAndReferencesAndNotInSource() throws {
        let view = host()
        view.display(.ready(presentation(.bibtex, text: "@misc{a, author = {Doe, Jane}, title = {Safe}, year = {2020}}", syntax: .bibtex)), locale: english)
        let caveat = PreviewStrings.text(.markupReferencesNotice)
        #expect(occurrences(of: caveat, in: status(view)) == 1)
        try select(.references, in: view)
        #expect(occurrences(of: caveat, in: status(view)) == 1)
        #expect(status(view).contains(PreviewStrings.text(.markupReferencesLanguageNote)))
        try select(.source, in: view)
        #expect(occurrences(of: caveat, in: status(view)) == 0)
    }

    @Test func theReferencesViewNoLongerRepeatsTheCaveatInsideItself() {
        // The caveat and the note about English citation terms are status lines (`MarkupRendering.notices`).
        let view = MarkupReferencesView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let modes = SafePreviewModes(presentation(.bibtex, text: "@misc{a, title = {T}}", syntax: .bibtex), locale: english)
        view.display(modes, mode: .references, style: testStyle())
        let labels = descendants(of: NSTextField.self, in: view).map(\.stringValue)
        #expect(!labels.contains { $0.contains(PreviewStrings.text(.markupReferencesNotice)) })
        #expect(!labels.contains { $0.contains(PreviewStrings.text(.markupReferencesLanguageNote)) })
        #expect(view.textView.string.contains("T"))
    }

    @Test func aConvertedBookKeepsItsStatusNoticeWhileItsRenderedTextHidesTheFlag() {
        let text = "---\ntitle: Book\ndrm: true\n---\n\n# Chapter\n\nText.\n"
        let view = host()
        view.display(.ready(presentation(.epub, text: text, syntax: .markdown)), locale: english)
        #expect(occurrences(of: PreviewStrings.text(.ebooksNoticeDRM), in: status(view)) == 1)
        #expect(!displayedText(view).contains("drm: true"))
        #expect(displayedText(view).hasPrefix(PreviewStrings.text(.documentFrontMatterTitle) + " Book"))
    }
}
