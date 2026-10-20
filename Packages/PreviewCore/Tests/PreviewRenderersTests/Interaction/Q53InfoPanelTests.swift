import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Proposed facade seams are empty/hidden for RED. Tests use native actions and an off-screen host only.
@Suite("Q53 bounded in-view preview information", .serialized)
@MainActor
struct Q53InfoPanelTests {
    private let english = Locale(identifier: "en_US")

    @Test func ownedCopyHasPluralAndLocaleAwareCountsAndCompleteCommandTemplates() {
        #expect(PreviewStrings.text(.previewInfoButtonLabel, languagePreferences: ["en"]) == "Preview information")
        #expect(PreviewStrings.text(.previewInfoOnThisMac, languagePreferences: ["en"]) == "Processed on this Mac")
        #expect(PreviewStrings.count(.previewInfoConcealedCount, 1, locale: english, languagePreferences: ["en"])
            == "1 likely secret concealed.")
        for locale in [english, Locale(identifier: "de_DE"), Locale(identifier: "tr_TR")] {
            for count in [0, 2, 12_345] {
                #expect(PreviewStrings.count(.previewInfoConcealedCount, count, locale: locale, languagePreferences: ["en"])
                    == count.formatted(.number.locale(locale)) + " likely secrets concealed.")
            }
        }
        #expect(PreviewStrings.format(.previewInfoCommand, arguments: ["Find", "⌘F"],
            locale: english, languagePreferences: ["en"]) == "Find — ⌘F")
        let keys: [PreviewStrings.Key] = [.previewInfoButtonLabel, .previewInfoOnThisMac, .previewInfoCommandsHeading]
        for language in ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"] {
            for key in keys {
                let value = PreviewStrings.text(key, languagePreferences: [language])
                #expect(!value.isEmpty && value != key.rawValue && value != PreviewStrings.text(.resourceUnavailable))
            }
            let concealed = PreviewStrings.count(.previewInfoConcealedCount, 12_345, locale: english, languagePreferences: [language])
            let command = PreviewStrings.format(.previewInfoCommand, arguments: ["Find", "⌘F"], locale: english,
                languagePreferences: [language])
            #expect(!concealed.isEmpty && !concealed.contains("%") && !concealed.contains("preview.info."))
            #expect(command.contains("⌘F") && !command.contains("%") && !command.contains("preview.info."))
        }
    }

    @Test func informationIsA22PointLabelledButtonAndTogglesTheInlinePanel() throws {
        let host = InteractionHarness(width: 800)
        defer { host.release() }
        show(presentation(), in: host)
        let button = try infoButton(host.view)
        #expect(button.bounds.width == PreviewChrome.infoButtonSide && button.bounds.height == PreviewChrome.infoButtonSide)
        #expect(button.accessibilityRole() == .button)
        #expect(button.accessibilityLabel() == PreviewStrings.text(.previewInfoButtonLabel))
        #expect(button.keyEquivalent.isEmpty)
        #expect(!host.view.infoPanelIsOpen && host.view.infoPanelView.isHidden)
        #expect(button.accessibilityValue() as? Int == 0)
        button.performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.infoPanelIsOpen && !host.view.infoPanelView.isHidden)
        #expect(button.accessibilityValue() as? Int == 1)
        #expect(host.view.infoPanelView.window === host.window)
        #expect(host.view.infoPanelView.isDescendant(of: host.view))
        button.performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        #expect(!host.view.infoPanelIsOpen && host.view.infoPanelView.isHidden)
        #expect(button.accessibilityValue() as? Int == 0)
    }

    @Test func panelCopyContainsOnlyOwnedProvenanceConcealedCountAndCurrentCommands() throws {
        let host = InteractionHarness(width: 800)
        defer { host.release() }
        host.view.providerName = "Acme Preview"
        show(presentation(redactions: 3), in: host)
        try infoButton(host.view).performClick(nil)
        let provider = PreviewStrings.format(.interactionProviderBadge, arguments: ["Acme Preview"], locale: english)
        let concealed = PreviewStrings.count(.previewInfoConcealedCount, 3, locale: english)
        #expect(Array(host.view.displayedInfoLines.prefix(4)) == [PreviewStrings.text(.readOnly),
            PreviewStrings.text(.previewInfoOnThisMac), provider, concealed])
        #expect(!host.view.displayedInfoLines.contains { $0.contains("Q53_SOURCE_VALUE") })
        #expect(host.view.displayedInfoLines.contains(PreviewStrings.text(.previewInfoCommandsHeading)))
        #expect(!host.view.displayedInfoCommands.isEmpty)
        for command in host.view.displayedInfoCommands {
            let help = PreviewStrings.format(.previewInfoCommand, arguments: [command.localizedTitle(locale: english),
                command.shortcutDescription], locale: english)
            #expect(host.view.displayedInfoLines.contains(help))
        }
        let fullText = host.view.displayedInfoLines.joined(separator: "\n")
        #expect(host.view.infoPanelView.accessibilityValue() as? String == fullText)
        let rowLabels = descendants(of: NSTextField.self, in: host.view.infoPanelView)
        #expect(rowLabels.map(\.stringValue) == host.view.displayedInfoLines)
        #expect(rowLabels.allSatisfy { $0.toolTip == $0.stringValue })
        host.view.providerName = nil
        #expect(host.view.infoPanelIsOpen && !host.view.displayedInfoLines.contains(provider))
        #expect(host.view.displayedInfoLines.contains(concealed))
    }

    @Test func sameDocumentModesAndStylesKeepThePanelOpenAndRefreshCommandHelp() throws {
        let host = InteractionHarness(width: 800)
        defer { host.release() }
        let safe = presentation(format: .markdown, syntax: .markdown, text: "# Q53 source\n\nQ53_SOURCE_VALUE")
        show(safe, in: host)
        try select(.source, in: host.view)
        try infoButton(host.view).performClick(nil)
        #expect(host.view.displayedInfoCommands.contains(.goToLine))
        let sourceCommands = host.view.displayedInfoCommands
        try select(.rendered, in: host.view)
        #expect(host.view.infoPanelIsOpen)
        #expect(!host.view.displayedInfoCommands.contains(.goToLine))
        #expect(host.view.displayedInfoCommands != sourceCommands)
        #expect(!host.press("l", .command), "Existing Rendered dispatch also declines source-line navigation")
        host.view.display(.ready(safe), typography: PreviewTypography(fontSize: 20), theme: .dark,
            syntaxStyle: PreviewSyntaxStyle(usesColor: false), locale: english)
        #expect(host.view.infoPanelIsOpen && !host.view.displayedInfoCommands.contains(.goToLine))
        try select(.source, in: host.view)
        #expect(host.view.infoPanelIsOpen && host.view.displayedInfoCommands == sourceCommands)
        #expect(host.press("l", .command), "Help follows the same command that dispatch accepts")
    }

    @Test func anOpenPanelNeverComputesProfileAndAReplacementOrStateClearsItsContent() throws {
        let host = InteractionHarness(width: 800)
        defer { host.release() }
        host.view.chromeScheduler = ManualChromeScheduler()
        let csv = presentation(format: .csv, syntax: .commaSeparated, text: "name,value\na,1\nb,2\n")
        show(csv, in: host)
        try infoButton(host.view).performClick(nil)
        #expect(host.view.infoPanelIsOpen && !host.view.dataProfileIsComputed)
        for mode in [.source, .table] as [NativePreviewMode] {
            try select(mode, in: host.view)
            #expect(host.view.infoPanelIsOpen && !host.view.dataProfileIsComputed)
        }
        host.view.display(.ready(csv), locale: english, resetsContentState: true)
        expectCleared(host.view)
        try infoButton(host.view).performClick(nil)
        host.view.showLoading()
        expectCleared(host.view)
        for outcome in [PreviewOutcome.unavailable(.missingFile), .disabledByUser(.csv), .cancelled] {
            show(csv, in: host)
            #expect(!host.view.infoPanelIsOpen)
            try infoButton(host.view).performClick(nil)
            host.view.display(outcome, locale: english)
            expectCleared(host.view)
            #expect(host.view.infoBadge.isHidden)
        }
        show(csv, in: host)
        try infoButton(host.view).performClick(nil)
        show(presentation(text: ""), in: host)
        expectCleared(host.view)
        show(csv, in: host)
        try infoButton(host.view).performClick(nil)
        host.view.showSettingsUnavailable()
        expectCleared(host.view)
        show(csv, in: host)
        try infoButton(host.view).performClick(nil)
        host.view.showSettingsConfigurationUnavailable()
        expectCleared(host.view)
        show(presentation(redactions: 1), in: host)
        try infoButton(host.view).performClick(nil)
        #expect(host.view.displayedInfoLines.contains(PreviewStrings.count(.previewInfoConcealedCount, 1, locale: english)))
        #expect(!host.view.displayedInfoLines.contains(PreviewStrings.count(.previewInfoConcealedCount, 3, locale: english)))
    }

    @Test func panelScrollIsBoundedAndOpeningItPreservesTheQ52SingleRowFacts() throws {
        let host = InteractionHarness(width: 800, height: 300)
        defer { host.release() }
        let safe = presentation(format: .json, syntax: .json, text: #"{"safe":[1,2]}"#)
        show(safe, in: host)
        let row = host.view.headerGuide.frame
        let facts = host.view.displayedFacts
        let factsFrame = host.view.convert(host.view.factsLabel.bounds, from: host.view.factsLabel)
        let contentHeight = host.view.contentGuide.frame.height
        try infoButton(host.view).performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        let panel = host.view.infoPanelView
        let panelFrame = host.view.convert(panel.bounds, from: panel)
        let scroll = try #require(descendants(of: NSScrollView.self, in: panel).first)
        let document = try #require(scroll.documentView)
        #expect(scroll.hasVerticalScroller && !scroll.hasHorizontalScroller)
        #expect(panelFrame.height > 0 && panelFrame.height <= host.view.safeAreaLayoutGuide.frame.height * 0.25 + 1)
        #expect(document.frame.height > scroll.contentSize.height, "The fixture exercises internal scrolling")
        #expect(host.view.contentGuide.frame.height < contentHeight)
        #expect(!host.view.hasAmbiguousLayout && !panel.hasAmbiguousLayout)
        #expect(host.view.headerGuide.frame == row && row.height <= PreviewChrome.headerHeight)
        #expect(host.view.displayedFacts == facts)
        #expect(host.view.convert(host.view.factsLabel.bounds, from: host.view.factsLabel) == factsFrame)
        let fullText = host.view.displayedInfoLines.joined(separator: "\n")
        #expect(panel.accessibilityValue() as? String == fullText)
        #expect(panel.isDescendant(of: host.view) && panel.window === host.window)
    }

    @Test func userDisclosurePostsOneLayoutAfterItsFinalStateAndRestylingIsQuiet() throws {
        let host = InteractionHarness(width: 800)
        defer { host.release() }
        let safe = presentation()
        show(safe, in: host)
        var expanded: [Bool] = []
        host.view.announcer.notificationHandler = { [weak view = host.view] element, notification, userInfo in
            guard let view, notification == .layoutChanged else { return }
            #expect(element === view && userInfo.isEmpty)
            expanded.append(view.infoPanelIsOpen)
        }
        let button = try infoButton(host.view)
        button.performClick(nil)
        #expect(expanded == [true])
        host.view.display(.ready(safe), typography: PreviewTypography(fontSize: 20), locale: english)
        #expect(expanded == [true] && host.view.infoPanelIsOpen)
        host.view.providerName = "Acme Preview"
        #expect(expanded == [true])
        button.performClick(nil)
        #expect(expanded == [true, false])
        host.view.display(.ready(safe), locale: english, resetsContentState: true)
        #expect(expanded == [true, false], "A programmatic refresh is not another disclosure action")
    }

    @Test func theInfoButtonHandsSpaceAndEscapeToItsParentUnchanged() throws {
        let host = InteractionHarness(width: 800)
        defer { host.release() }
        let catcher = Q53InfoKeyCatcher(frame: host.view.frame)
        host.window.contentView = catcher
        catcher.addSubview(host.view)
        show(presentation(), in: host)
        let button = try infoButton(host.view)
        for (code, character) in [(PreviewKeyCode.space, " "), (PreviewKeyCode.escape, "\u{1B}")] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: host.window.windowNumber, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: code))
            #expect(!host.view.performKeyEquivalent(with: event))
            button.keyDown(with: event)
        }
        #expect(catcher.received == [PreviewKeyCode.space, PreviewKeyCode.escape])
        #expect(!host.view.infoPanelIsOpen)
    }

    private func infoButton(_ view: NativePreviewView) throws -> NSButton {
        try #require((view.infoBadge as NSView) as? NSButton, "Q53 replaces the passive image with a native button")
    }
    private func show(_ safe: TextPresentation, in host: InteractionHarness) {
        host.view.display(.ready(safe), locale: english, resetsContentState: true)
        host.view.layoutSubtreeIfNeeded()
    }
    private func select(_ mode: NativePreviewMode, in view: NativePreviewView) throws {
        view.modeControl.selectedSegment = try #require(view.displayedModes.firstIndex(of: mode))
        #expect(view.modeControl.sendAction(view.modeControl.action, to: view.modeControl.target))
        view.layoutSubtreeIfNeeded()
    }
    private func expectCleared(_ view: NativePreviewView) {
        #expect(!view.infoPanelIsOpen && view.infoPanelView.isHidden && view.displayedInfoLines.isEmpty)
        #expect(view.displayedInfoCommands.isEmpty)
        #expect(((view.infoPanelView.accessibilityValue() as? String) ?? "").isEmpty)
    }
    private func presentation(redactions: Int = 0, format: FormatID = .plainText, syntax: TextSyntax = .plain,
                              text: String = "Q53_SOURCE_VALUE") -> TextPresentation {
        .init(formatID: format, text: text, lineCount: text.components(separatedBy: "\n").count,
            byteCount: text.utf8.count, encoding: .utf8, redactionCount: redactions, syntax: syntax)
    }
}

@MainActor
private final class Q53InfoKeyCatcher: NSView {
    private(set) var received: [UInt16] = []
    override func keyDown(with event: NSEvent) { received.append(event.keyCode) }
}
