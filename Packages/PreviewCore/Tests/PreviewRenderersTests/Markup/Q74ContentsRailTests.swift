import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Something else in the window that holds keyboard focus, so a test can see whether the rail takes it.
@MainActor
private final class RailFocusStub: NSView {
    override var acceptsFirstResponder: Bool { true }
}

/// The next responder of a view under test: records the keys handed on to it.
@MainActor
private final class RailKeyCatcher: NSResponder {
    private(set) var received: [UInt16] = []
    override func keyDown(with event: NSEvent) { received.append(event.keyCode) }
}

/// Everything the rail could say or do without the reader asking.
@MainActor
private final class RailRecorder {
    var texts: [String] = []
    var notifications: [NSAccessibility.Notification] = []
    var revealed: [NSRange] = []
}

/// A rail installed beside a neighbour view in a host, inside a window, with a private pasteboard.
@MainActor
private struct RailFixture {
    let rail: MarkupContentsRail
    let host: NSView
    let neighbour: NSView
    let focus: RailFocusStub
    let window: NSWindow
    let board: NSPasteboard
    let recorder: RailRecorder

    init(width: CGFloat = 900, direction: NSUserInterfaceLayoutDirection = .leftToRight) {
        let rail = MarkupContentsRail(frame: .zero)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
        // Leading and trailing resolve against the host's direction when the constraints are installed, as they
        // do in the preview, whose host carries the process direction from launch.
        host.userInterfaceLayoutDirection = direction
        let neighbour = NSView(frame: .zero)
        let focus = RailFocusStub(frame: .zero)
        let board = NSPasteboard(name: NSPasteboard.Name("q74-\(UUID().uuidString)"))
        let recorder = RailRecorder()
        rail.install(in: host, top: host.topAnchor, bottom: host.bottomAnchor)
        neighbour.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(neighbour)
        host.addSubview(focus)
        NSLayoutConstraint.activate([
            neighbour.leadingAnchor.constraint(equalTo: rail.trailingAnchor),
            neighbour.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            neighbour.topAnchor.constraint(equalTo: host.topAnchor),
            neighbour.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = host
        rail.pasteboard = board
        rail.onReveal = { recorder.revealed.append($0) }
        rail.announcer?.handler = { recorder.texts.append($0) }
        rail.announcer?.notificationHandler = { _, notification, _ in recorder.notifications.append(notification) }
        self.rail = rail
        self.host = host
        self.neighbour = neighbour
        self.focus = focus
        self.window = window
        self.board = board
        self.recorder = recorder
    }

    func release() { board.releaseGlobally() }

    /// Shows the rail for `headings` as a wide pane in Rendered mode, unless told otherwise.
    func show(_ headings: [MarkupHeading], mode: NativePreviewMode = .rendered, width: CGFloat? = nil,
              eligible: Bool = true, style: SafeModeStyle? = nil) {
        rail.sync(headings: headings, mode: mode, hostWidth: width ?? host.frame.width, isEligible: eligible,
                  style: style ?? railStyle())
    }
}

@MainActor
private func railStyle(dark: Bool = false, fontSize: Double = 13) -> SafeModeStyle {
    SafeModeStyle(typography: PreviewTypography(fontSize: fontSize),
                  palette: NativeTextPalette(theme: dark ? .dark : .light, isDark: dark, increasedContrast: false),
                  syntaxStyle: .init(), locale: Locale(identifier: "en"))
}

/// A colour as its sRGB bytes, so a layer's colour can be compared with a palette role.
@MainActor
private func rgbHex(_ color: CGColor?) -> UInt32? {
    guard let color, let converted = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return nil }
    func byte(_ value: CGFloat) -> UInt32 { UInt32((value * 255).rounded()) }
    return byte(converted.redComponent) << 16 | byte(converted.greenComponent) << 8 | byte(converted.blueComponent)
}

/// Five headings in a 1,000-unit text, the last near the end.
private func railHeadings(titles: [String] = ["One", "Two", "Three", "Four", "Five"]) -> [MarkupHeading] {
    let starts = [0, 100, 250, 400, 900]
    let levels = [1, 2, 2, 1, 3]
    return starts.indices.map { index in
        MarkupHeading(level: levels[index], title: titles[index],
                      range: NSRange(location: starts[index], length: titles[index].utf16.count))
    }
}

private func reading(_ location: Int, _ length: Int) -> ContentsViewport {
    ContentsViewport(visible: NSRange(location: location, length: length), textLength: 1_000)
}

@MainActor
private func railKey(_ keyCode: UInt16, typed: String, in window: NSWindow,
                     modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                  windowNumber: window.windowNumber, context: nil, characters: typed,
                                  charactersIgnoringModifiers: typed, isARepeat: false, keyCode: keyCode))
}

@Suite("Q74 Contents rail", .serialized)
@MainActor
struct Q74ContentsRailTests {
    private var downArrow: String { String(UnicodeScalar(NSDownArrowFunctionKey)!) }

    // MARK: Offering the rail

    @Test func aWideRenderedDocumentShowsTheRailAndTheListFollowsTheReader() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        fixture.show(railHeadings())
        let rail = fixture.rail
        #expect(rail.isOffered && !rail.isHidden && rail.railWidth == ContentsRailPolicy.expandedWidth)
        #expect(rail.list.headings == railHeadings())
        // Nothing is selected until the reader's position is known.
        #expect(rail.list.tableView.selectedRow == -1)
        rail.track(reading(120, 100))
        #expect(rail.list.tableView.selectedRow == 1 && rail.tracker.current == 1)
        rail.track(reading(500, 100))
        #expect(rail.list.tableView.selectedRow == 3 && rail.tracker.current == 3)
        rail.track(reading(0, 40))
        #expect(rail.list.tableView.selectedRow == 0)
        // Above the first heading nothing is current.
        rail.sync(headings: Array(railHeadings().dropFirst()), mode: .rendered, hostWidth: 900, isEligible: true,
                  style: railStyle())
        rail.track(reading(120, 100))
        #expect(rail.list.tableView.selectedRow == 0)
        rail.track(reading(0, 60))
        #expect(rail.list.tableView.selectedRow == -1 && rail.tracker.current == nil)
    }

    @Test func compactPanesOtherModesAndIneligibleHostsDoNotShowTheRail() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        let rail = fixture.rail
        let cases: [(NativePreviewMode, CGFloat, Bool, [MarkupHeading])] = [
            (.source, 900, true, railHeadings()),
            (.contents, 900, true, railHeadings()),
            (.rendered, ContentsRailPolicy.minimumHostWidth - ContentsRailPolicy.hysteresis - 1, true, railHeadings()),
            (.rendered, 900, false, railHeadings()),
            (.rendered, 900, true, Array(railHeadings().prefix(1)))
        ]
        for (mode, width, eligible, headings) in cases {
            fixture.show(headings, mode: mode, width: width, eligible: eligible)
            fixture.host.layoutSubtreeIfNeeded()
            #expect(!rail.isOffered && rail.isHidden && rail.railWidth == 0, "\(mode) \(width) \(eligible)")
            #expect(rail.list.headings.isEmpty)
            // Hidden, the rail takes no room: the view beside it starts at the host's leading edge.
            #expect(fixture.neighbour.frame.minX == 0 && fixture.neighbour.frame.width == fixture.host.bounds.width)
        }
    }

    @Test func theNeighbourStartsAtTheRailsTrailingEdgeInBothDirections() throws {
        for direction in [NSUserInterfaceLayoutDirection.leftToRight, .rightToLeft] {
            let fixture = RailFixture(direction: direction)
            defer { fixture.release() }
            fixture.show(railHeadings())
            fixture.host.layoutSubtreeIfNeeded()
            let width = ContentsRailPolicy.expandedWidth
            #expect(fixture.rail.frame.width == width, "\(direction)")
            if direction == .leftToRight {
                #expect(fixture.rail.frame.minX == 0 && fixture.neighbour.frame.minX == width)
            } else {
                #expect(fixture.rail.frame.maxX == fixture.host.bounds.maxX)
                #expect(fixture.neighbour.frame.maxX == fixture.rail.frame.minX)
            }
        }
    }

    @Test func aHostNarrowerThanTheRailNeverMakesItOverflow() throws {
        let fixture = RailFixture(width: 200)
        defer { fixture.release() }
        fixture.show(railHeadings(), width: 900)
        fixture.host.layoutSubtreeIfNeeded()
        #expect(fixture.rail.frame.maxX <= fixture.host.bounds.maxX && fixture.rail.frame.minX >= 0)
    }

    @Test func theWidthDecisionKeepsItsStateInsideTheHysteresisBand() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        let rail = fixture.rail
        fixture.show(railHeadings())
        #expect(rail.isOffered)
        rail.hostWidthChanged(ContentsRailPolicy.minimumHostWidth)
        #expect(rail.isOffered)
        rail.hostWidthChanged(ContentsRailPolicy.minimumHostWidth - ContentsRailPolicy.hysteresis - 1)
        #expect(!rail.isOffered && rail.railWidth == 0 && rail.list.headings.isEmpty)
        rail.hostWidthChanged(ContentsRailPolicy.minimumHostWidth)
        #expect(!rail.isOffered)
        rail.hostWidthChanged(ContentsRailPolicy.minimumHostWidth + ContentsRailPolicy.hysteresis)
        #expect(rail.isOffered && rail.list.headings == railHeadings())
    }

    // MARK: Following the reader

    @Test func followingTheReaderNeverMovesFocusSpeaksOrNavigates() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        fixture.show(railHeadings())
        #expect(fixture.window.makeFirstResponder(fixture.focus))
        for location in stride(from: 0, through: 960, by: 60) {
            fixture.rail.track(reading(location, 40))
        }
        fixture.show(railHeadings(), style: railStyle(dark: true))
        fixture.rail.setCollapsed(true)
        fixture.rail.track(reading(120, 100))
        fixture.rail.setCollapsed(false)
        #expect(fixture.window.firstResponder === fixture.focus)
        #expect(!fixture.rail.list.hasKeyboardFocus)
        #expect(fixture.recorder.texts.isEmpty && fixture.recorder.notifications.isEmpty)
        #expect(fixture.recorder.revealed.isEmpty)
        #expect(fixture.rail.list.tableView.selectedRow == 1)
    }

    @Test func whileTheListHasFocusTheReadersOwnSelectionIsLeftAlone() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        fixture.show(railHeadings())
        let table = fixture.rail.list.tableView
        fixture.rail.track(reading(120, 100))
        #expect(fixture.window.makeFirstResponder(table))
        table.selectRowIndexes(IndexSet(integer: 4), byExtendingSelection: false)
        fixture.rail.track(reading(500, 100))
        // The tracker follows the scroll, the selection the reader made by keyboard stays.
        #expect(fixture.rail.tracker.current == 3 && table.selectedRow == 4)
        #expect(fixture.window.makeFirstResponder(fixture.focus))
        fixture.rail.track(reading(500, 100))
        #expect(table.selectedRow == 3)
    }

    @Test func aReplacementDocumentStartsWithNoCurrentSection() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        fixture.show(railHeadings())
        fixture.rail.track(reading(500, 100))
        #expect(fixture.rail.list.tableView.selectedRow == 3)
        let replacement = railHeadings(titles: ["A", "B", "C", "D", "E"])
        fixture.show(replacement)
        #expect(fixture.rail.list.headings == replacement)
        #expect(fixture.rail.tracker.current == nil && fixture.rail.list.tableView.selectedRow == -1)
    }

    @Test func restylingTheSameDocumentKeepsTheCurrentSection() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        fixture.show(railHeadings())
        fixture.rail.track(reading(230, 100))
        #expect(fixture.rail.list.tableView.selectedRow == 2)
        fixture.show(railHeadings(), style: railStyle(dark: true, fontSize: 18))
        #expect(fixture.rail.tracker.current == 2 && fixture.rail.list.tableView.selectedRow == 2)
        #expect(fixture.recorder.texts.isEmpty && fixture.recorder.revealed.isEmpty)
    }

    @Test func theViewportProviderFeedsTheTrackerAndNothingIsReadWhileTheRailIsHidden() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        var asked = 0
        fixture.rail.viewport = { asked += 1; return reading(260, 100) }
        fixture.show(railHeadings(), mode: .source)
        fixture.rail.viewportChanged()
        #expect(asked == 0)
        fixture.show(railHeadings())
        fixture.rail.viewportChanged()
        #expect(asked == 1 && fixture.rail.list.tableView.selectedRow == 2)
        fixture.rail.viewport = { nil }
        fixture.rail.viewportChanged()
        #expect(fixture.rail.list.tableView.selectedRow == 2)
    }

    // MARK: Choosing a heading

    @Test func choosingAHeadingRevealsItsRangeAndKeepsItCurrentWhileItIsInView() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        let list = railHeadings()
        fixture.show(list)
        fixture.rail.list.activate(row: 3)
        #expect(fixture.recorder.revealed == [list[3].range])
        #expect(fixture.rail.tracker.current == 3 && fixture.rail.list.tableView.selectedRow == 3)
        // The scroll that reveals it leaves the heading near the bottom, under the anchor of an earlier section.
        fixture.rail.track(reading(330, 160))
        #expect(fixture.rail.tracker.current == 3 && fixture.rail.list.tableView.selectedRow == 3)
        // Scrolling it out of view hands the choice back to the reader's position.
        fixture.rail.track(reading(110, 100))
        #expect(fixture.rail.tracker.current == 1 && fixture.rail.list.tableView.selectedRow == 1)
        #expect(fixture.recorder.revealed.count == 1)
    }

    @Test func returnOnTheFocusedListRevealsTheSelectedHeadingButSpaceAndArrowsDoNot() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        fixture.show(railHeadings())
        let table = fixture.rail.list.tableView
        let catcher = RailKeyCatcher()
        table.nextResponder = catcher
        fixture.rail.track(reading(120, 100))
        // Without focus the arrows are nobody's business.
        let down = try railKey(125, typed: downArrow, in: fixture.window)
        #expect(fixture.window.makeFirstResponder(fixture.focus))
        #expect(!table.performKeyEquivalent(with: down))
        #expect(table.selectedRow == 1 && !fixture.rail.list.hasKeyboardFocus)
        #expect(fixture.window.makeFirstResponder(table))
        table.keyDown(with: try railKey(PreviewKeyCode.returnKey, typed: "\r", in: fixture.window))
        #expect(fixture.recorder.revealed == [railHeadings()[1].range])
        table.keyDown(with: try railKey(PreviewKeyCode.space, typed: " ", in: fixture.window))
        table.keyDown(with: try railKey(PreviewKeyCode.escape, typed: "\u{1B}", in: fixture.window))
        #expect(catcher.received == [PreviewKeyCode.space, PreviewKeyCode.escape])
        #expect(fixture.recorder.revealed.count == 1)
    }

    // MARK: Folding

    @Test func foldingTheRailLeavesOnlyItsToggleAndOpeningItRestoresTheCurrentSection() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        fixture.show(railHeadings())
        let rail = fixture.rail
        rail.track(reading(230, 100))
        rail.toggleButton.performClick(nil)
        fixture.host.layoutSubtreeIfNeeded()
        #expect(rail.isCollapsed && rail.list.isHidden && rail.railWidth == ContentsRailPolicy.collapsedWidth)
        #expect(rail.frame.width == ContentsRailPolicy.collapsedWidth)
        #expect(fixture.neighbour.frame.minX == ContentsRailPolicy.collapsedWidth)
        #expect(rail.toggleButton.accessibilityLabel() == PreviewStrings.text(.markupContentsRailShow))
        #expect(rail.toggleButton.toolTip == PreviewStrings.text(.markupContentsRailShow))
        // The tracker keeps following while the list is folded away.
        rail.track(reading(500, 100))
        rail.toggleButton.performClick(nil)
        fixture.host.layoutSubtreeIfNeeded()
        #expect(!rail.isCollapsed && !rail.list.isHidden && rail.frame.width == ContentsRailPolicy.expandedWidth)
        #expect(rail.list.tableView.selectedRow == 3)
        #expect(rail.toggleButton.accessibilityLabel() == PreviewStrings.text(.markupContentsRailHide))
    }

    @Test func foldingTheRailMovesFocusOffTheHiddenList() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        fixture.show(railHeadings())
        #expect(fixture.window.makeFirstResponder(fixture.rail.list.tableView))
        fixture.rail.setCollapsed(true)
        #expect(fixture.window.firstResponder !== fixture.rail.list.tableView)
        #expect(!fixture.rail.list.hasKeyboardFocus)
    }

    @Test func withdrawingTheRailReleasesFocusInsideIt() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        fixture.show(railHeadings())
        #expect(fixture.window.makeFirstResponder(fixture.rail.list.tableView))
        fixture.show(railHeadings(), mode: .source)
        #expect(fixture.window.firstResponder !== fixture.rail.list.tableView)
        #expect(fixture.rail.isHidden)
    }

    @Test func theToggleHandsSpaceAndEscapeToQuickLookAndAnswersReturn() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        fixture.show(railHeadings())
        let toggle = fixture.rail.toggleButton
        let catcher = RailKeyCatcher()
        toggle.nextResponder = catcher
        toggle.keyDown(with: try railKey(PreviewKeyCode.space, typed: " ", in: fixture.window))
        toggle.keyDown(with: try railKey(PreviewKeyCode.escape, typed: "\u{1B}", in: fixture.window))
        #expect(catcher.received == [PreviewKeyCode.space, PreviewKeyCode.escape])
        #expect(!fixture.rail.isCollapsed)
        toggle.keyDown(with: try railKey(PreviewKeyCode.returnKey, typed: "\r", in: fixture.window))
        #expect(fixture.rail.isCollapsed)
        #expect(catcher.received.count == 2 && fixture.recorder.texts.isEmpty)
    }

    // MARK: Copy and services

    @Test func copyGoesThroughTheInjectedPasteboardAndIsReportedOnce() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        fixture.show(railHeadings())
        fixture.rail.track(reading(230, 100))
        var events: [PreviewCopyEvent] = []
        fixture.rail.copyHandler = { events.append($0) }
        #expect(fixture.rail.list.tableView.pasteboard === fixture.board)
        fixture.rail.list.tableView.copy(nil)
        #expect(fixture.board.string(forType: .string) == "Three")
        #expect(events == [.rows(1)])
        #expect(fixture.recorder.texts.isEmpty)
    }

    @Test func theCopyPolicyOfThePreviewReachesTheList() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        let tags = "\u{E0061}\u{E0062}\u{E007F}"
        fixture.show(railHeadings(titles: ["One", "Two", "Plain" + tags, "Four", "Five"]))
        fixture.rail.tagCopyPolicy = { true }
        fixture.rail.track(reading(230, 100))
        var events: [PreviewCopyEvent] = []
        fixture.rail.copyHandler = { events.append($0) }
        fixture.rail.list.tableView.copy(nil)
        #expect(fixture.board.string(forType: .string) == "Plain")
        #expect(events == [.rows(1).removingTags(3)])
    }

    @Test func theRailTakesThePreviewsAnnouncerThroughTheListItHosts() throws {
        let rail = MarkupContentsRail(frame: .zero)
        let announcer = PreviewAnnouncer()
        rail.announcer = announcer
        #expect(rail.list.tableView.announcer === announcer && rail.announcer === announcer)
        let services: [any PreviewAnnouncing] = [rail]
        #expect(services.count == 1)
    }

    // MARK: Appearance and accessibility

    @Test func rowsStayInTheRailsTypeSizeAndTheContentsModeKeepsTheReadersSize() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        let style = railStyle(fontSize: 40)
        fixture.show(railHeadings(), style: style)
        let railCell = try #require(fixture.rail.list.tableView(fixture.rail.list.tableView, viewFor: nil, row: 1) as? ContentsCell)
        let railFont = try #require(railCell.field.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(railFont.pointSize <= ContentsRailPolicy.maximumRowPointSize)
        let mode = MarkupContentsView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        mode.display(headings: railHeadings(), style: style)
        let modeCell = try #require(mode.tableView(mode.tableView, viewFor: nil, row: 1) as? ContentsCell)
        let modeFont = try #require(modeCell.field.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(modeFont.pointSize == 40)
        // The rail indents less per level than the Contents mode, which has the whole width.
        railCell.layoutSubtreeIfNeeded()
        modeCell.layoutSubtreeIfNeeded()
        #expect(railCell.field.frame.minX < modeCell.field.frame.minX)
    }

    @Test func theRailIsPaintedWithPaletteRolesAndItsToggleIsLabelledAndHelped() throws {
        let fixture = RailFixture()
        defer { fixture.release() }
        for dark in [false, true] {
            let palette = NativeTextPalette(theme: dark ? .dark : .light, isDark: dark, increasedContrast: false)
            fixture.show(railHeadings(), style: railStyle(dark: dark))
            #expect(rgbHex(fixture.rail.layer?.backgroundColor) == rgbHex(palette.background.cgColor), "dark \(dark)")
            let rule = fixture.rail.subviews.first { rgbHex($0.layer?.backgroundColor) == rgbHex(palette.hairline.cgColor) }
            #expect(rule != nil, "dark \(dark)")
            #expect(fixture.rail.toggleButton.contentTintColor == palette.muted, "dark \(dark)")
            let title = try #require(descendants(of: NSTextField.self, in: fixture.rail).first {
                $0.stringValue == PreviewStrings.text(.previewModeContents)
            })
            #expect(title.textColor == palette.muted && !title.isAccessibilityElement())
        }
        let toggle = fixture.rail.toggleButton
        #expect(toggle.accessibilityRole() == .button && toggle.image != nil)
        #expect(toggle.accessibilityLabel() == PreviewStrings.text(.markupContentsRailHide))
        #expect(toggle.accessibilityHelp() == PreviewStrings.text(.markupContentsRailHelp))
        #expect(fixture.rail.list.tableView.accessibilityLabel() == PreviewStrings.text(.previewModeContents))
        #expect(!fixture.rail.isAccessibilityElement() && fixture.rail.accessibilityRole() == .group)
    }
}
