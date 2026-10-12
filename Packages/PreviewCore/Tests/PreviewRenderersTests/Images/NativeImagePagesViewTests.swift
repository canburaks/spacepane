import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Native image pages view", .serialized)
@MainActor
struct NativeImagePagesViewTests {
    private func modes(for images: [PreviewImage], total: Int? = nil) -> SafePreviewModes {
        var modes = SafePreviewModes(presentation(.comicBook, text: "{}", syntax: .json, images: images), locale: Locale(identifier: "en"))
        modes.imagePageTotal = total
        return modes
    }

    private func makeView(probe: DecodeProbe, concurrency: Int = 2, size: NSSize = NSSize(width: 600, height: 400)) -> NativeImagePagesView {
        let view = NativeImagePagesView(frame: NSRect(origin: .zero, size: size),
                                        scheduler: ImagePageScheduler(maximumConcurrent: concurrency, decode: probe.decode()))
        view.layoutSubtreeIfNeeded()
        return view
    }

    // MARK: Layout and labels

    @Test func placeholderFramesExistForEveryPageBeforeAnythingDecodes() {
        let probe = DecodeProbe(gated: true)
        let view = makeView(probe: probe)
        view.display(modes(for: testPages(30)), mode: .pages, style: testStyle())
        #expect(view.pageCount == 30)
        #expect(view.pageFrames.count == 30)
        #expect(view.pageFrames.allSatisfy { $0.width > 0 && $0.height > 0 })
        // The scroll content spans every page, so the scroller reflects the whole document.
        #expect((view.documentView?.frame.height ?? 0) >= view.pageFrames.last!.maxY)
        view.clear()
        probe.open()
    }

    @Test func eachPageIsALabeledImageElementWithLocalizedNumbers() throws {
        let probe = DecodeProbe(gated: true)
        let view = makeView(probe: probe)
        view.display(modes(for: testPages(3), total: 120), mode: .pages, style: testStyle())
        let first = try #require(view.pageView(at: 0))
        #expect(first.isAccessibilityElement())
        #expect(first.accessibilityRole() == .image)
        #expect(first.accessibilityLabel() == "Page 1 of 120")
        #expect(try #require(view.pageView(at: 2)).accessibilityLabel() == "Page 3 of 120")
        #expect(view.accessibilityLabel() == PreviewStrings.text(.previewModePages))
        #expect(view.accessibilityHelp() == PreviewStrings.text(.ebooksPagesHelp))
        view.clear()
        probe.open()
    }

    @Test func labelsFormatNumbersForThePresentationLocaleAndFollowTheImageRole() {
        let page = PreviewImage(data: Data([1]), pixelWidth: 1, pixelHeight: 1, role: .page)
        let arabic = NativeImagePagesView.label(for: page, number: 3, total: 12, locale: Locale(identifier: "ar_SA"))
        #expect(arabic.contains("٣") && arabic.contains("١٢"))
        let english = NativeImagePagesView.label(for: page, number: 1_234, total: 5_678, locale: Locale(identifier: "en_US"))
        #expect(english == "Page 1,234 of 5,678")
        let cover = PreviewImage(data: Data([1]), pixelWidth: 1, pixelHeight: 1, role: .cover)
        #expect(NativeImagePagesView.label(for: cover, number: 1, total: 1, locale: .current) == PreviewStrings.text(.ebooksPagesCover))
        let figure = PreviewImage(data: Data([1]), pixelWidth: 1, pixelHeight: 1, role: .figure)
        #expect(NativeImagePagesView.label(for: figure, number: 2, total: 4, locale: Locale(identifier: "en")) == "Figure 2 of 4")
        let icon = PreviewImage(data: Data([1]), pixelWidth: 1, pixelHeight: 1, role: .icon)
        #expect(NativeImagePagesView.label(for: icon, number: 1, total: 2, locale: Locale(identifier: "en")) == "Image 1 of 2")
        // Figures and pages count independently within one document.
        let mixed = [page, figure, page, figure]
        #expect(NativeImagePagesView.numbering(for: mixed) == [1, 1, 2, 2])
    }

    // MARK: Lazy decoding

    @Test func onlyPagesNearTheViewportDecodeAndFarPagesStayPlaceholders() async {
        let probe = DecodeProbe()
        let view = makeView(probe: probe)
        view.display(modes(for: testPages(200)), mode: .pages, style: testStyle())
        #expect(await waitUntil { !view.decodedPageIndices.isEmpty })
        #expect(await waitUntil { probe.started == probe.finished })
        let decoded = view.decodedPageIndices
        #expect(decoded.count <= 12)
        #expect(decoded.allSatisfy { $0 < 12 })
        #expect(probe.started < 20)
        view.clear()
    }

    @Test func scrollingDecodesTheNewNeighborhoodAndReleasesPagesFarBehind() async {
        let probe = DecodeProbe()
        let view = makeView(probe: probe)
        view.display(modes(for: testPages(200)), mode: .pages, style: testStyle())
        #expect(await waitUntil { view.decodedPageIndices.contains(0) })
        view.scrollToEnd()
        let last = 199
        #expect(await waitUntil { view.decodedPageIndices.contains(last) })
        // Pages two viewports behind were released; the first pages hold no bitmap any more.
        #expect(await waitUntil { !view.decodedPageIndices.contains(0) })
        #expect(view.decodedPageIndices.allSatisfy { $0 > 150 })
        view.clear()
    }

    @Test func decodesNeverOverlapBeyondTheSchedulerCap() async {
        let probe = DecodeProbe()
        let view = makeView(probe: probe, concurrency: 2, size: NSSize(width: 600, height: 1_200))
        view.display(modes(for: testPages(40, width: 100, height: 100)), mode: .pages, style: testStyle())
        #expect(await waitUntil { probe.finished >= 5 })
        #expect(probe.maximumConcurrent <= 2)
        view.clear()
    }

    @Test func residentBitmapMemoryStaysUnderTheByteBudget() async {
        let probe = DecodeProbe()
        let view = makeView(probe: probe, size: NSSize(width: 600, height: 1_000))
        view.residentByteLimit = 130_000   // About two 100 x 140 pages of four-byte pixels.
        view.display(modes(for: testPages(40)), mode: .pages, style: testStyle())
        #expect(await waitUntil { !view.decodedPageIndices.isEmpty })
        #expect(await waitUntil { probe.started == probe.finished })
        #expect(view.residentBytes <= 130_000)
        #expect(view.decodedPageIndices.count <= 2)
        view.clear()
    }

    // MARK: Clear and replacement

    @Test func clearCancelsPendingDecodesAndAFinishedLateResultNeverRevivesAPage() async {
        let probe = DecodeProbe(gated: true)
        let view = makeView(probe: probe)
        view.display(modes(for: testPages(10)), mode: .pages, style: testStyle())
        #expect(await waitUntil { probe.started >= 1 })
        view.clear()
        #expect(view.pageCount == 0)
        #expect(view.decodedPageIndices.isEmpty)
        probe.open()
        #expect(await waitUntil { probe.finished == probe.started })
        try? await Task.sleep(for: .milliseconds(30))
        #expect(view.pageCount == 0)
        #expect(view.decodedPageIndices.isEmpty)
    }

    @Test func aReplacementDocumentStartsFromScratchAndKeepsNoPriorBitmaps() async {
        let probe = DecodeProbe()
        let view = makeView(probe: probe)
        view.display(modes(for: testPages(20)), mode: .pages, style: testStyle())
        #expect(await waitUntil { view.decodedPageIndices.contains(0) })
        view.display(modes(for: testPages(3, width: 60, height: 90)), mode: .pages, style: testStyle())
        #expect(view.pageCount == 3)
        #expect(view.pageFrames.count == 3)
        #expect(await waitUntil { view.decodedPageIndices.count == 3 })
        view.clear()
    }

    @Test func redisplayingTheSamePagesOnlyRestylesWithoutRebuildingOrRedecoding() async {
        let probe = DecodeProbe()
        let view = makeView(probe: probe)
        let content = modes(for: testPages(5))
        view.display(content, mode: .pages, style: testStyle())
        #expect(await waitUntil { !view.decodedPageIndices.isEmpty })
        #expect(await waitUntil { probe.started == probe.finished })
        let decoded = view.decodedPageIndices
        let started = probe.started
        let first = view.pageView(at: 0)
        view.display(content, mode: .pages, style: testStyle())
        view.display(content, mode: .pages, style: testStyle(locale: Locale(identifier: "de")))
        #expect(view.pageView(at: 0) === first)
        #expect(probe.started == started)
        #expect(view.decodedPageIndices == decoded)
        view.clear()
    }

    @Test func aFailedDecodeLeavesAnAnnotatedPlaceholderInsteadOfRetrying() async {
        let view = NativeImagePagesView(frame: NSRect(x: 0, y: 0, width: 600, height: 400),
                                        scheduler: ImagePageScheduler(maximumConcurrent: 2, decode: { _, _ in nil }))
        view.layoutSubtreeIfNeeded()
        view.display(modes(for: testPages(2)), mode: .pages, style: testStyle())
        #expect(await waitUntil { view.pageView(at: 0)?.isUnavailable == true })
        #expect(view.pageView(at: 0)?.accessibilityHelp() == PreviewStrings.text(.ebooksPagesUnavailable))
        #expect(view.decodedPageIndices.isEmpty)
        view.clear()
    }

    @Test func otherModesAreIgnored() {
        let probe = DecodeProbe(gated: true)
        let view = makeView(probe: probe)
        view.display(modes(for: testPages(3)), mode: .summary, style: testStyle())
        #expect(view.pageCount == 0)
        probe.open()
    }

    // MARK: Keyboard

    @Test func keyboardMovesByLinesPagesAndToTheEnds() {
        let probe = DecodeProbe()
        let view = makeView(probe: probe)
        view.display(modes(for: testPages(60)), mode: .pages, style: testStyle())
        func top() -> CGFloat { view.contentView.documentVisibleRect.minY }
        #expect(top() == 0)
        #expect(view.handleNavigationKey(keyEvent(125, modifiers: [])))              // Down arrow
        #expect(top() == 40)
        #expect(view.handleNavigationKey(keyEvent(126)))                              // Up arrow
        #expect(top() == 0)
        let page = view.contentView.bounds.height * 0.9
        #expect(!view.handleNavigationKey(keyEvent(49, characters: " ")))             // Space is Quick Look's
        #expect(!view.handleNavigationKey(keyEvent(49, characters: " ", modifiers: .shift)))
        #expect(top() == 0)
        #expect(view.handleNavigationKey(keyEvent(121)))                              // Page Down
        #expect(abs(top() - page) < 1)
        #expect(view.handleNavigationKey(keyEvent(116)))                              // Page Up
        #expect(top() == 0)
        #expect(view.handleNavigationKey(keyEvent(125, modifiers: .command)))         // Command-Down
        let maximum = (view.documentView?.frame.height ?? 0) - view.contentView.bounds.height
        #expect(abs(top() - maximum) < 1)
        #expect(view.handleNavigationKey(keyEvent(126, modifiers: .command)))         // Command-Up
        #expect(top() == 0)
        #expect(view.handleNavigationKey(keyEvent(119)))                              // End
        #expect(abs(top() - maximum) < 1)
        #expect(view.handleNavigationKey(keyEvent(115)))                              // Home
        #expect(top() == 0)
        #expect(!view.handleNavigationKey(keyEvent(0, characters: "a")))
        view.clear()
    }

    @Test func leftAndRightArrowsMoveToThePreviousAndNextPage() {
        let probe = DecodeProbe()
        let view = makeView(probe: probe)
        view.display(modes(for: testPages(10)), mode: .pages, style: testStyle())
        let frames = view.pageFrames
        #expect(view.handleNavigationKey(keyEvent(124)))                              // Right: next page
        #expect(view.topPageIndex == 1)
        #expect(view.contentView.documentVisibleRect.minY == frames[1].minY - ImagePagesLayout.verticalInset)
        #expect(view.handleNavigationKey(keyEvent(124)))
        #expect(view.topPageIndex == 2)
        #expect(view.handleNavigationKey(keyEvent(123)))                              // Left: previous page
        #expect(view.topPageIndex == 1)
        view.scrollToEnd()
        #expect(view.handleNavigationKey(keyEvent(124)))                              // Already at the end: stays put
        view.clear()
    }

    @Test func theColumnTakesFocusInItsDocumentContainerSoKeysReachIt() {
        let view = NativeImagePagesView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        // The scroll view is not the responder; its document container is, and keys travel up to the column.
        #expect(view.keyboardFocusTarget?.acceptsFirstResponder == true)
        view.clear()
    }
}
