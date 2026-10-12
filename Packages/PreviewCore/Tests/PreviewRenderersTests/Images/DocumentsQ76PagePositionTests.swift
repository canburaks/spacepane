import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

// Decision 027, Q-76 (review DM-22) with Q-51: the page at the top of the column is reported as a typed limits notice
// ("Page 3 of 1,200") through the notice API the preview's one bottom strip already reads. The column only reports;
// the hosting preview decides where the sentence goes.

@MainActor
private final class PositionLog {
    private(set) var notices: [PresentationNotice?] = []
    func record(_ notice: PresentationNotice?) { notices.append(notice) }
    var texts: [String?] { notices.map { $0?.text } }
}

@Suite("Pages position notice", .serialized)
@MainActor
struct DocumentsQ76PagePositionTests {
    private let enUS = Locale(identifier: "en_US")

    private func modes(for images: [PreviewImage], total: Int? = nil) -> SafePreviewModes {
        var modes = SafePreviewModes(presentation(.comicBook, text: "{}", syntax: .json, images: images), locale: Locale(identifier: "en"))
        modes.imagePageTotal = total
        return modes
    }

    /// A column whose decodes never finish, so only the position is under test.
    private func makeView(_ probe: DecodeProbe, height: CGFloat = 400) -> NativeImagePagesView {
        let view = NativeImagePagesView(frame: NSRect(x: 0, y: 0, width: 600, height: height),
                                        scheduler: ImagePageScheduler(maximumConcurrent: 2, decode: probe.decode()))
        view.layoutSubtreeIfNeeded()
        return view
    }

    // MARK: The notice

    @Test func theTopPageIsAPositionLimitWithLocaleFormattedNumbers() throws {
        let probe = DecodeProbe(gated: true)
        let view = makeView(probe)
        view.display(modes(for: testPages(10), total: 1_200), mode: .pages, style: testStyle(locale: enUS))
        #expect(view.positionNotice == PresentationNotice(kind: .limit, text: "Page 1 of 1,200"))
        view.scrollToPage(offset: 2)
        #expect(view.positionNotice == PresentationNotice(kind: .limit, text: "Page 3 of 1,200"))
        // At the end the viewport shows the last pages; the notice names whichever page is at its top.
        view.scrollToEnd()
        let top = try #require(view.topPageIndex)
        #expect(top > 2)
        #expect(view.positionNotice?.text == "Page \(top + 1) of 1,200")
        view.clear()
        probe.open()
    }

    @Test func theNumbersFollowTheStyleLocale() {
        let probe = DecodeProbe(gated: true)
        let view = makeView(probe)
        view.display(modes(for: testPages(5), total: 1_200), mode: .pages, style: testStyle(locale: Locale(identifier: "de_DE")))
        #expect(view.positionNotice?.text.contains("1.200") == true)
        view.display(modes(for: testPages(5), total: 12), mode: .pages, style: testStyle(locale: Locale(identifier: "ar_SA")))
        view.scrollToPage(offset: 2)
        let text = view.positionNotice?.text ?? ""
        #expect(text.contains("\u{0663}") && text.contains("\u{0661}\u{0662}"))
        view.clear()
        probe.open()
    }

    /// A view that is in no window sizes its pages with the main screen's scale (1 on a 1x display, 2 on a Retina
    /// one), and pages are never magnified past twice their size in points. Three 100 x 140 pixel pages fill 970
    /// points of column at 1x and 550 at 2x, so a 400 point viewport can scroll the second page to the top at 1x
    /// but not at 2x: the column ends first and the first page stays on top. This pins that behaviour for both
    /// scales without depending on the host's display.
    @Test func aShortColumnCannotScrollALaterPageToTheTop() {
        let sizes = Array(repeating: CGSize(width: 100, height: 140), count: 3)
        for (scale, content) in [(CGFloat(1), CGFloat(970)), (2, 550), (3, 406)] {
            let layout = ImagePagesLayout(pixelSizes: sizes, viewportWidth: 600, backingScale: scale)
            #expect(layout.contentSize.height == content, "scale \(scale)")
            let reachableTop = layout.contentSize.height - 400
            let secondPageTop = layout.frames[1].minY - ImagePagesLayout.verticalInset
            #expect((secondPageTop <= reachableTop) == (scale == 1), "scale \(scale)")
            // In a 120 point viewport every scale can bring the second page to the top.
            #expect(secondPageTop <= layout.contentSize.height - 120, "scale \(scale)")
        }
    }

    @Test func figuresAndCoversAreNamedLikeTheirAccessibilityLabels() {
        let probe = DecodeProbe(gated: true)
        // A viewport short enough that the second page can reach the top at any display scale (see above).
        let view = makeView(probe, height: 120)
        view.display(modes(for: testPages(3, role: .figure)), mode: .pages, style: testStyle(locale: enUS))
        view.scrollToPage(offset: 1)
        #expect(view.positionNotice?.text == "Figure 2 of 3")
        #expect(view.positionNotice?.text == view.pageView(at: 1)?.accessibilityLabel())
        view.clear()
        probe.open()
    }

    @Test func aLoneCoverHasNoPositionButAComicWithOnePageOfManyDoes() {
        let probe = DecodeProbe(gated: true)
        let view = makeView(probe)
        view.display(modes(for: testPages(1, role: .cover)), mode: .pages, style: testStyle(locale: enUS))
        #expect(view.positionNotice == nil)
        view.display(modes(for: testPages(1), total: 1_200), mode: .pages, style: testStyle(locale: enUS))
        #expect(view.positionNotice?.text == "Page 1 of 1,200")
        view.clear()
        probe.open()
    }

    @Test func nothingIsReportedBeforePagesExistOrAfterTheyAreCleared() {
        let probe = DecodeProbe(gated: true)
        let view = makeView(probe)
        #expect(view.positionNotice == nil)
        view.display(modes(for: testPages(4)), mode: .pages, style: testStyle(locale: enUS))
        view.clear()
        #expect(view.positionNotice == nil)
        probe.open()
    }

    // MARK: The report

    @Test func theHostHearsOnlyAboutChangesOfThePageAtTheTop() {
        let probe = DecodeProbe(gated: true)
        let view = makeView(probe)
        let log = PositionLog()
        view.onPositionChange = { log.record($0) }
        view.display(modes(for: testPages(10), total: 1_200), mode: .pages, style: testStyle(locale: enUS))
        #expect(log.texts == ["Page 1 of 1,200"])
        // A line of scrolling inside the first page changes nothing, however many events it takes.
        #expect(view.handleNavigationKey(keyEvent(125)))
        view.refreshVisiblePages()
        #expect(log.texts == ["Page 1 of 1,200"])
        view.scrollToPage(offset: 1)
        #expect(log.texts == ["Page 1 of 1,200", "Page 2 of 1,200"])
        view.scrollToPage(offset: -1)
        #expect(log.texts.last == "Page 1 of 1,200")
        view.clear()
        #expect(log.notices.count == 4)
        #expect(log.texts.last == .some(nil))
        probe.open()
    }

    @Test func aNewLocaleWordsTheSamePositionAgain() {
        let probe = DecodeProbe(gated: true)
        let view = makeView(probe)
        let log = PositionLog()
        view.onPositionChange = { log.record($0) }
        view.display(modes(for: testPages(10), total: 1_200), mode: .pages, style: testStyle(locale: enUS))
        view.display(modes(for: testPages(10), total: 1_200), mode: .pages, style: testStyle(locale: Locale(identifier: "de_DE")))
        #expect(log.texts.count == 2)
        let last = log.texts.last ?? nil
        #expect(last?.contains("1.200") == true)
        view.clear()
        probe.open()
    }

    @Test func aReplacementDocumentStartsFromItsOwnFirstPage() throws {
        let probe = DecodeProbe(gated: true)
        let view = makeView(probe)
        view.display(modes(for: testPages(10)), mode: .pages, style: testStyle(locale: enUS))
        view.scrollToEnd()
        let scrolled = try #require(view.topPageIndex)
        #expect(scrolled > 0)
        view.display(modes(for: testPages(4, width: 60, height: 90)), mode: .pages, style: testStyle(locale: enUS))
        #expect(view.positionNotice?.text == "Page 1 of 4")
        view.clear()
        probe.open()
    }
}
