import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Zoom, info badge and reload rendering", .serialized)
@MainActor
struct ZoomBadgeAndReloadRenderingTests {
    // MARK: Zoom

    @Test func commandPlusMinusAndZeroResizeTheTextForThisPreviewOnly() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.show(plainPresentation(numberedLines(10)), typography: PreviewTypography(fontSize: 13))
        #expect(fontSize(host) == 13)
        #expect(!(try host.status()).contains("⌘0"))
        #expect(host.press("=", .command))
        #expect(fontSize(host) == 14)
        #expect(host.press("+", [.command, .shift]))
        #expect(fontSize(host) == 15)
        #expect(try host.status().contains("⌘0"))
        #expect(host.press("-", .command))
        #expect(fontSize(host) == 14)
        #expect(host.press("0", .command))
        #expect(fontSize(host) == 13)
        #expect(!(try host.status()).contains("⌘0"))
        // The saved typography is untouched: zoom only changes what is drawn.
        #expect(host.view.typography == PreviewTypography(fontSize: 13))
    }

    @Test func zoomIsClampedAndAKeyAtTheLimitIsStillConsumed() throws {
        let top = InteractionHarness()
        defer { top.release() }
        top.show(plainPresentation("x"), typography: PreviewTypography(fontSize: 47))
        #expect(top.press("=", .command) && fontSize(top) == 48)
        #expect(top.press("=", .command) && fontSize(top) == 48)
        #expect(top.view.effectiveTypography.isValid)
        let bottom = InteractionHarness()
        defer { bottom.release() }
        bottom.show(plainPresentation("x"), typography: PreviewTypography(fontSize: 8))
        #expect(bottom.press("-", .command) && fontSize(bottom) == 8)
        #expect(bottom.view.effectiveTypography.fontSize == PreviewTypography.fontSizeRange.lowerBound)
        // Nothing displayed: the shortcut is not the preview's.
        let empty = InteractionHarness()
        defer { empty.release() }
        #expect(!empty.press("=", .command))
    }

    @Test func zoomSurvivesAReloadAndRestylingButNotANewRequest() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.show(plainPresentation(numberedLines(10)), typography: PreviewTypography(fontSize: 13))
        host.press("=", .command)
        host.press("=", .command)
        #expect(fontSize(host) == 15)
        // The same request with new content (a live reload) and a restyle keep it.
        host.view.display(.ready(plainPresentation(numberedLines(12))), typography: PreviewTypography(fontSize: 13))
        #expect(fontSize(host) == 15)
        host.view.display(.ready(plainPresentation(numberedLines(12))), typography: PreviewTypography(fontSize: 20))
        #expect(fontSize(host) == 22)
        // A new request starts from the saved size again.
        host.show(plainPresentation(numberedLines(12)), typography: PreviewTypography(fontSize: 13), resetsContentState: true)
        #expect(fontSize(host) == 13)
        host.press("=", .command)
        host.view.showLoading()
        host.show(plainPresentation("again"), typography: PreviewTypography(fontSize: 13))
        #expect(fontSize(host) == 13)
    }

    @Test func zoomKeepsTheSelectionAndRestylesOutlineAndTableModes() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.show(plainPresentation("alpha beta gamma"), typography: PreviewTypography(fontSize: 13))
        host.textView.setSelectedRange(NSRange(location: 6, length: 4))
        host.press("=", .command)
        #expect(host.textView.selectedRange() == NSRange(location: 6, length: 4))

        let outlineHost = InteractionHarness()
        defer { outlineHost.release() }
        let json = #"{"members":[{"path":"a","type":"file"}]}"#
        outlineHost.show(plainPresentation(json, format: .folder, syntax: .json), typography: PreviewTypography(fontSize: 20))
        let outline = try #require(outlineHost.view.outlineView.documentView as? NSOutlineView)
        let before = outline.rowHeight
        #expect(outlineHost.press("=", .command))
        #expect(outline.rowHeight > before)
        let item = try #require(outline.item(atRow: 0))
        let field = try #require(outlineHost.view.outlineView.outlineView(outline, viewFor: outline.tableColumns[0], item: item) as? NSTextField)
        let font = try #require(field.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 22)
        outlineHost.press("0", .command)
        #expect(outline.rowHeight == before)

        let tableHost = InteractionHarness()
        defer { tableHost.release() }
        let csv = "name,note\nalice,hello\n"
        tableHost.show(plainPresentation(csv, format: .csv, syntax: .commaSeparated), typography: PreviewTypography(fontSize: 20))
        let table = try #require(descendants(of: NativeTablePreviewView.self, in: tableHost.view).first)
        let tableBefore = table.tableView.rowHeight
        #expect(tableHost.press("=", .command))
        #expect(table.tableView.rowHeight > tableBefore)
    }

    // MARK: Info badge

    @Test func theInfoBadgeCarriesTheCaptionsOnlyWhileAPreviewIsShown() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let badge = host.view.infoBadge
        let readOnly = PreviewStrings.text(.readOnly)
        host.show(plainPresentation("safe"))
        // The captions left the status line, which now holds only this document's notices.
        #expect(try host.status().isEmpty)
        #expect(!badge.isHidden && badge.toolTip == readOnly)
        host.view.providerName = "Acme Preview"
        let provider = PreviewStrings.format(.interactionProviderBadge, arguments: ["Acme Preview"])
        #expect(badge.toolTip == readOnly + "\n" + provider)
        #expect(badge.accessibilityLabel() == PreviewStrings.text(.previewInfoButtonLabel))
        #expect(try host.status().isEmpty)
        // Not a preview: loading, unavailable and disabled states keep their message and show no badge.
        host.view.showLoading()
        #expect(badge.isHidden && badge.toolTip == nil && badge.accessibilityLabel() == nil)
        #expect(try !host.status().isEmpty)
        host.view.display(.unavailable(.missingFile))
        #expect(try badge.isHidden && !host.status().contains("Acme Preview"))
        host.view.display(.disabledByUser(.json))
        #expect(try badge.isHidden && !host.status().contains("Acme Preview"))
        host.show(plainPresentation("safe again"))
        #expect(badge.toolTip == readOnly + "\n" + provider)
        host.view.providerName = nil
        #expect(badge.toolTip == readOnly)
        host.view.providerName = ""
        #expect(badge.toolTip == readOnly)
        // A notice that changes what copying returns stays visible.
        host.show(plainPresentation("token = [concealed]", redactions: 1))
        #expect(!host.view.findingsBanner.isHidden)
        #expect(host.view.findingsBanner.summaryLabel.stringValue == PreviewStrings.count(.findingSummaryConcealed, 1, locale: host.view.presentationLocale))
        #expect(try host.status().isEmpty)
    }

    @Test func theConfiguredNameIsShownVerbatimAndTheBadgeFollowsTheLanguage() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.show(plainPresentation("safe"))
        for name in ["100% %@ Ünï 日本", "Name\nWith Break".replacingOccurrences(of: "\n", with: " ")] {
            host.view.providerName = name
            #expect(host.view.infoBadge.toolTip?.contains(name) == true)
        }
        // The caption is a localized resource with the name as its argument in every language.
        let template = PreviewStrings.text(.interactionProviderBadge)
        #expect(template.contains("%@") || template.contains("%1$@"))
        for language in ["tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"] {
            let localized = PreviewStrings.text(.interactionProviderBadge, languagePreferences: [language])
            #expect(localized != template, "\(language) must not fall back to English")
            #expect(localized.contains("%@"), "\(language)")
        }
        #expect(NativePreviewPane(outcome: .cancelled, typography: .init(), generation: UUID()).providerName == nil)
        #expect(NativePreviewPane(outcome: .cancelled, typography: .init(), generation: UUID(), providerName: "X").providerName == "X")
    }

    @Test func theBadgeSharesTheModeRowAndAnEmptyStatusRowCollapses() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.view.providerName = "Acme Preview"
        host.show(plainPresentation("name,note\nalice,hello\n", format: .csv, syntax: .commaSeparated))
        // Alignment rects: the symbol image view's frame adds padding above and below the glyph.
        let badge = host.view.infoBadge.alignmentRect(forFrame: host.view.infoBadge.frame)
        let modes = host.view.modeControl
        let modeRect = host.view.convert(modes.bounds, from: modes)
        let status = host.view.statusLabel
        #expect(!modes.isHidden && status.isHidden && status.frame.height == 0)
        #expect(abs(badge.midY - modeRect.midY) < 0.5)
        #expect(modeRect.maxX <= badge.minX - 8)
        #expect(badge.maxX == host.view.bounds.maxX - 12)
        // Nothing sits above the mode row but its top margin.
        #expect(host.view.bounds.maxY - modeRect.maxY <= 8)
    }

    @Test func withoutModesTheBadgeSharesTheFactsRowAndNotesStayBelowIt() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.show(plainPresentation(numberedLines(20)))
        let view = host.view
        let status = view.statusLabel
        var badge: NSRect { view.infoBadge.alignmentRect(forFrame: view.infoBadge.frame) }
        let facts = view.factsLabel
        // Facts and the badge keep one row; empty notes take no height.
        #expect(status.isHidden && status.stringValue.isEmpty && status.frame.height == 0)
        #expect(abs(badge.midY - facts.frame.midY) < 0.5 && badge.height == PreviewInfoBadge.side)
        #expect(badge.maxX == view.bounds.maxX - 12)
        let textFrame = view.convert(view.scrollView.bounds, from: view.scrollView)
        #expect(textFrame.maxY <= badge.minY)
        #expect(view.bounds.maxY - textFrame.maxY <= 10 + PreviewInfoBadge.side + 8)
        let initialRow = view.headerGuide.frame
        let safe = TextPresentation(formatID: .plainText, text: "safe reformatted text", lineCount: 1,
            byteCount: 21, encoding: .utf8, redactionCount: 0, isReformatted: true)
        view.display(.ready(safe))
        view.layoutSubtreeIfNeeded()
        #expect(view.headerGuide.frame == initialRow)
        #expect(!status.isHidden && status.stringValue == PreviewStrings.text(.codeNoticeReformatted))
        #expect(status.frame.maxY < badge.minY)
        #expect(status.alignmentRect(forFrame: status.frame).width == view.bounds.width - 2 * PreviewChrome.inset)
    }

    // MARK: Reload rendering

    @Test func newContentUnderTheSameRequestKeepsSelectionAndScrollPosition() throws {
        let host = InteractionHarness(height: 220)
        defer { host.release() }
        let original = numberedLines(300)
        host.show(plainPresentation(original), typography: PreviewTypography(wrapsLines: false))
        let selection = (original as NSString).range(of: "line 150")
        host.textView.setSelectedRange(selection)
        let scroll = host.view.scrollView
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 1_500))
        scroll.reflectScrolledClipView(scroll.contentView)
        let origin = scroll.contentView.bounds.origin
        // The file grew at its end.
        let grown = original + "\nline 301\nline 302"
        host.show(plainPresentation(grown), typography: PreviewTypography(wrapsLines: false))
        #expect(host.textView.string == grown)
        #expect(host.textView.selectedRange() == selection)
        #expect(abs(scroll.contentView.bounds.origin.y - origin.y) < 1)
        // A shorter file clamps instead of trapping.
        host.show(plainPresentation("line 1\nline 2"), typography: PreviewTypography(wrapsLines: false))
        let clamped = host.textView.selectedRange()
        #expect(NSMaxRange(clamped) <= (host.textView.string as NSString).length)
        #expect(scroll.contentView.bounds.origin.y <= max(0, host.textView.frame.height - scroll.contentView.bounds.height))
    }

    @Test func aNewRequestOrADifferentFormatStartsAtTheTop() throws {
        let host = InteractionHarness(height: 220)
        defer { host.release() }
        let original = numberedLines(300)
        host.show(plainPresentation(original))
        host.textView.setSelectedRange((original as NSString).range(of: "line 150"))
        host.view.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 1_500))
        host.show(plainPresentation(original + "\nmore"), resetsContentState: true)
        #expect(host.textView.selectedRange() == NSRange(location: 0, length: 0))
        #expect(host.view.scrollView.contentView.bounds.origin.y == 0)
        host.textView.setSelectedRange((original as NSString).range(of: "line 150"))
        host.view.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 1_500))
        host.show(plainPresentation(#"{"a":1}"#, format: .json, syntax: .json))
        #expect(host.textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test func theModeSurvivesAReloadAndADeletedFileShowsTheUnavailableState() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.show(plainPresentation("# One\n**two**", format: .markdown, syntax: .markdown))
        let control = host.view.modeControl
        control.selectedSegment = 1
        #expect(control.sendAction(control.action, to: control.target))
        host.show(plainPresentation("# One\n**two**\nthree", format: .markdown, syntax: .markdown))
        #expect(control.selectedSegment == 1)
        #expect(host.textView.string.contains("three") && !host.textView.string.contains("**"))
        // The file was deleted.
        host.view.display(.unavailable(.missingFile))
        // The state names what happened and what to do next: its title and body, in the status text.
        #expect(try host.status() == PreviewStrings.text(.failureTitleMissingFile) + "\n" + PreviewStrings.text(.failureBodyMissingFile))
        #expect(host.textView.string.isEmpty)
        #expect(host.view.copyAllText == nil)
        // And came back: shown again from the top.
        host.show(plainPresentation("# Back", format: .markdown, syntax: .markdown))
        #expect(host.textView.string.contains("Back"))
    }

    @Test func anOutlineKeepsItsOpenRowsThroughAReload() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let first = #"{"members":[{"path":"a","type":"file"},{"path":"b","type":"directory"}]}"#
        host.show(plainPresentation(first, format: .folder, syntax: .json))
        let outline = try #require(host.view.outlineView.documentView as? NSOutlineView)
        // Open everything the reader can open.
        var index = 0
        while index < outline.numberOfRows {
            outline.expandItem(outline.item(atRow: index), expandChildren: true)
            index += 1
        }
        let opened = outline.numberOfRows
        outline.selectRowIndexes(IndexSet(integer: min(2, opened - 1)), byExtendingSelection: false)
        let selectedValue = (outline.item(atRow: outline.selectedRow) as? OutlineItem)?.node.value
        let second = #"{"members":[{"path":"a","type":"file"},{"path":"b","type":"directory"},{"path":"c","type":"file"}]}"#
        host.show(plainPresentation(second, format: .folder, syntax: .json))
        #expect(outline.numberOfRows >= opened)
        #expect((outline.item(atRow: outline.selectedRow) as? OutlineItem)?.node.value == selectedValue)
    }
}

extension ZoomBadgeAndReloadRenderingTests {
    /// The point size the displayed text actually uses.
    func fontSize(_ host: InteractionHarness) -> CGFloat? {
        (host.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
    }
}
