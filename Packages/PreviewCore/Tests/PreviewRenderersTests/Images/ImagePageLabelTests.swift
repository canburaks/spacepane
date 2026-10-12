import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// A page's archive member path or file name is untrusted document text that never passes the privacy filter
/// or the hidden-character scan, so `PreviewImage` carries no adapter-chosen label (decision 027, Q-02): the
/// localized "Page n of m" label is the only name a page has, and no page may show, speak or draw anything else.
@Suite("Image page labels", .serialized)
@MainActor
struct ImagePageLabelTests {
    private func pages(_ count: Int) -> [PreviewImage] {
        (0..<count).map { index in
            PreviewImage(data: Data("page-\(index)".utf8), pixelWidth: 100, pixelHeight: 140, role: .page)
        }
    }

    private func modes(for images: [PreviewImage]) -> SafePreviewModes {
        SafePreviewModes(presentation(.comicBook, text: "{}", syntax: .json, images: images), locale: Locale(identifier: "en"))
    }

    private func makeView(decode: @escaping ImagePageScheduler.Decode) -> NativeImagePagesView {
        let view = NativeImagePagesView(frame: NSRect(x: 0, y: 0, width: 600, height: 400),
                                        scheduler: ImagePageScheduler(maximumConcurrent: 2, decode: decode))
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func everyView(in root: NSView) -> [NSView] {
        [root] + descendants(of: NSView.self, in: root)
    }

    /// Everything the view tree exposes as words: tooltips and the accessibility attributes that carry text.
    private func exposedText(in root: NSView) -> [String] {
        everyView(in: root).flatMap { view -> [String] in
            [view.toolTip, view.accessibilityLabel(), view.accessibilityHelp(), view.accessibilityValue() as? String].compactMap { $0 }
        }
    }

    @Test func theImageContractCarriesNoTextBesidesItsPixels() {
        // Every stored property is listed so that a reintroduced name or label field fails here.
        let fields = Set(Mirror(reflecting: pages(1)[0]).children.compactMap(\.label))
        #expect(fields == ["data", "pixelWidth", "pixelHeight", "role"])
    }

    @Test func pagesExposeOnlyTheirLocalizedPositionLabels() throws {
        let probe = DecodeProbe(gated: true)
        let view = makeView(decode: probe.decode())
        view.display(modes(for: pages(3)), mode: .pages, style: testStyle())
        #expect(view.pageCount == 3)
        let expected = Set((1...3).map { "Page \($0) of 3" })
        for index in 0..<3 {
            let page = try #require(view.pageView(at: index))
            #expect(page.toolTip == nil)
            #expect(page.accessibilityLabel() == "Page \(index + 1) of 3")
            #expect(page.caption == "Page \(index + 1) of 3")
        }
        let exposed = exposedText(in: view)
        #expect(exposed.contains("Page 1 of 3"))
        // Only the position labels and the view's own localized words may appear; never a file name.
        for text in exposed where !expected.contains(text) {
            #expect(!text.contains(".png") && !text.contains("/"), "\(text)")
        }
        view.clear()
        probe.open()
    }

    @Test func anUnavailablePageShowsTheLocalizedHint() async throws {
        let view = makeView(decode: { _, _ in nil })
        view.display(modes(for: pages(2)), mode: .pages, style: testStyle())
        #expect(await waitUntil { view.pageView(at: 0)?.isUnavailable == true })
        let page = try #require(view.pageView(at: 0))
        #expect(page.toolTip == PreviewStrings.text(.ebooksPagesUnavailable))
        #expect(page.accessibilityHelp() == PreviewStrings.text(.ebooksPagesUnavailable))
        #expect(page.accessibilityLabel() == "Page 1 of 2")
        view.clear()
    }

    @Test func exposedTextNeverCarriesHiddenCharacters() throws {
        let probe = DecodeProbe(gated: true)
        let view = makeView(decode: probe.decode())
        view.display(modes(for: pages(2)), mode: .pages, style: testStyle())
        let hidden: Set<UInt32> = [0x202E, 0x200B, 0x200E, 0x200F]
        for text in exposedText(in: view) {
            #expect(!text.unicodeScalars.contains { hidden.contains($0.value) }, "\(text.debugDescription)")
        }
        view.clear()
        probe.open()
    }
}
