import AppKit
import Foundation
import Testing
@testable import PreviewRenderers

/// The two native controls preserve one supplied capability list and dispatch contract.
@Suite("Q55 native compact mode control", .serialized)
@MainActor
struct Q55CompactModeControlTests {
    private let offered: [NativePreviewMode] = [.source, .outline, .table, .profile, .rendered, .contents,
        .references, .pages, .files, .tree]

    @Test func compactUsesANativePullDownWithEveryOfferedModeInTheSameOrder() throws {
        let control = makeControl(.compact, selected: .profile)
        #expect(control.visibleControl === control.pullDownControl)
        #expect(!control.pullDownControl.isHidden && control.segmentedControl.isHidden)
        let menu = try #require(control.pullDownControl.menu)
        let choices = menu.items.filter { $0.action != nil }
        #expect(choices.map(\.title) == offered.map { PreviewStrings.text($0.title, languagePreferences: ["en"]) })
        #expect(choices.map(\.tag) == Array(offered.indices))
        #expect(choices.count == 10, "A density change must not drop capabilities or invent a five-mode policy")
        #expect(choices.filter { $0.state == .on }.map(\.tag) == [3])
        #expect(menu.items.first?.title == "Profile" && menu.items.first?.action == nil)
        #expect(control.pullDownControl.accessibilityLabel() == "View mode")
        #expect(control.pullDownControl.accessibilityValue() as? String == "Profile")
        #expect(control.pullDownControl.toolTip == "Profile")
        #expect(choices.allSatisfy { $0.keyEquivalent.isEmpty }, "The facade owns the existing mode chords")
        #expect(choices.first?.toolTip == PreviewCommand.mode(1).shortcutDescription)
        #expect(choices.last?.toolTip == nil, "The tenth mode must not advertise a nonexistent digit chord")
    }

    @Test func menuAndSegmentsSendTheSameTypedRequestAndDensityChangesSendNone() throws {
        let control = makeControl(.compact, selected: .source)
        var requests: [NativePreviewMode] = []
        control.onSelectMode = { requests.append($0) }
        let menu = try #require(control.pullDownControl.menu)
        #expect(menu.items.first?.isEnabled == false && menu.items.first?.tag == -1)
        menu.performActionForItem(at: 0) // The closed title is not another selectable mode.
        #expect(requests.isEmpty)
        menu.performActionForItem(at: 4) // Title + Source, Outline, Table, Profile.
        #expect(requests == [.profile])
        control.display(offered, selected: .profile, density: .compact, languagePreferences: ["en"])
        control.setDensity(.regular)
        #expect(control.visibleControl === control.segmentedControl)
        #expect(control.segmentedControl.selectedSegment == 3)
        #expect(requests == [.profile])
        control.segmentedControl.selectedSegment = 2
        #expect(control.segmentedControl.sendAction(control.segmentedControl.action, to: control.segmentedControl.target))
        #expect(requests == [.profile, .table])
        control.display(offered, selected: .table, density: .regular, languagePreferences: ["en"])
        control.setDensity(.compact)
        #expect(requests == [.profile, .table])
        #expect(control.pullDownControl.accessibilityValue() as? String == "Table")
        #expect(control.pullDownControl.menu?.items.filter { $0.state == .on }.map(\.tag) == [2])
    }

    @Test func replacingCapabilitiesRejectsOldMenuItemsAndInvalidIndexes() throws {
        let control = makeControl(.compact, selected: .profile)
        var requests: [NativePreviewMode] = []
        control.onSelectMode = { requests.append($0) }
        let oldMenu = try #require(control.pullDownControl.menu)
        control.display([.source, .outline], selected: .source, density: .compact, languagePreferences: ["en"])
        oldMenu.performActionForItem(at: 2) // A retained old Outline row must not act on a new generation.
        #expect(requests.isEmpty)
        let menu = try #require(control.pullDownControl.menu)
        let item = try #require(menu.items.last)
        item.tag = -1
        menu.performActionForItem(at: menu.items.count - 1)
        #expect(requests.isEmpty)
        item.tag = 999
        menu.performActionForItem(at: menu.items.count - 1)
        #expect(requests.isEmpty)
    }

    @Test func aSingleModeAndClearLeaveNoVisibleControlOrOldAccessibilityValue() {
        let control = makeControl(.compact, selected: .profile)
        control.display([.source], selected: .source, density: .compact, languagePreferences: ["en"])
        #expect(control.visibleControl == nil && control.isHidden)
        #expect(control.segmentedControl.isHidden && control.pullDownControl.isHidden)
        #expect(control.intrinsicContentSize == .zero)
        control.clear()
        #expect(control.pullDownControl.menu == nil)
        #expect(control.pullDownControl.toolTip == nil)
        #expect(((control.pullDownControl.accessibilityValue() as? String) ?? "").isEmpty)
        #expect(((control.segmentedControl.accessibilityValue() as? String) ?? "").isEmpty)
        control.display([.source, .outline], selected: .outline, density: .compact, languagePreferences: ["en"])
        #expect(control.pullDownControl.accessibilityValue() as? String == "Outline")
    }

    @Test(arguments: ["de", "ru", "bn"])
    func expandedLabelsStayCompleteInTheNativeMenuAndAccessibility(language: String) throws {
        let control = PreviewModeControlView(frame: .zero)
        control.display(offered, selected: .contents, density: .compact, languagePreferences: [language])
        let title = PreviewStrings.text(.previewModeContents, languagePreferences: [language])
        let menu = try #require(control.pullDownControl.menu)
        #expect(menu.items.first?.title == title)
        #expect(control.pullDownControl.accessibilityValue() as? String == title)
        #expect(menu.items.filter { $0.action != nil }.map(\.title) == offered.map {
            PreviewStrings.text($0.title, languagePreferences: [language])
        })
        #expect(control.pullDownControl.accessibilityLabel() == PreviewStrings.text(.previewModeControlLabel,
            languagePreferences: [language]))
    }

    @Test func closedControlsForwardSpaceAndEscapeWithoutSwitchingModes() throws {
        let catcher = Q55ModeKeyCatcher(frame: NSRect(x: 0, y: 0, width: 600, height: 80))
        let control = makeControl(.compact, selected: .source)
        catcher.addSubview(control)
        var requests: [NativePreviewMode] = []
        control.onSelectMode = { requests.append($0) }
        for density in [PreviewChrome.Density.compact, .regular] {
            control.setDensity(density)
            let active = try #require(control.visibleControl)
            for code in [PreviewKeyCode.space, PreviewKeyCode.escape] {
                let event = try key(code)
                active.keyDown(with: event)
            }
        }
        #expect(catcher.received == [PreviewKeyCode.space, PreviewKeyCode.escape,
            PreviewKeyCode.space, PreviewKeyCode.escape])
        #expect(requests.isEmpty)
    }

    private func makeControl(_ density: PreviewChrome.Density, selected: NativePreviewMode) -> PreviewModeControlView {
        let control = PreviewModeControlView(frame: NSRect(x: 0, y: 0, width: 500, height: 28))
        control.display(offered, selected: selected, density: density, languagePreferences: ["en"])
        return control
    }

    private func key(_ code: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
    }
}

@MainActor
private final class Q55ModeKeyCatcher: NSView {
    private(set) var received: [UInt16] = []
    override func keyDown(with event: NSEvent) { received.append(event.keyCode) }
}
