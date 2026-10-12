import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Regression guard for the existing hide API after density becomes an active gutter consumer.
@Suite("Q55 cached gutter eligibility", .serialized)
@MainActor
struct Q55GutterEligibilityTests {
    @Test func explicitlyHidingLineNumbersClearsEligibilityUntilTheNextOrdinarySourceStylePass() throws {
        let host = InteractionHarness(width: PreviewChrome.compactWidth + PreviewChrome.compactHysteresis + 30)
        defer { host.release() }
        let presentation = plainPresentation(#"{"items":[1,2,3]}"#, format: .json, syntax: .json)
        let typography = PreviewTypography(showsLineNumbers: true)
        host.view.display(.ready(presentation), typography: typography, locale: Locale(identifier: "en_US"))
        host.view.layoutSubtreeIfNeeded()
        let content = try #require(descendants(of: PreviewTextContentView.self, in: host.view).first)
        #expect(!host.view.lineNumberGutter.isHidden)
        content.hideLineNumbers()
        host.view.forcedDensity = .compact
        host.view.layoutSubtreeIfNeeded()
        host.view.forcedDensity = .regular
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.lineNumberGutter.isHidden && host.view.lineNumberGutter.bounds.width == 0)
        #expect(host.view.textView.string == presentation.text)
        host.view.display(.ready(presentation), typography: typography, locale: Locale(identifier: "en_US"))
        host.view.layoutSubtreeIfNeeded()
        #expect(!host.view.lineNumberGutter.isHidden, "Only a new style pass may re-enable an explicitly hidden gutter")
        let outline = try #require(host.view.displayedModes.firstIndex(of: .outline)) + 1
        #expect(host.view.selectMode(number: outline))
        #expect(host.view.lineNumberGutter.isHidden)
        host.view.forcedDensity = .compact
        host.view.layoutSubtreeIfNeeded()
        host.view.forcedDensity = .regular
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.lineNumberGutter.isHidden && host.view.lineNumberGutter.bounds.width == 0)
        #expect(!host.view.outlineView.isHidden && host.view.textView.isHidden)
    }
}
