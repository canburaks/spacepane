import Foundation
import Testing
@testable import PreviewRenderers

/// The companion's own sentences that review findings reworded: what a switch enables, and words a person who
/// never opens Xcode can read. English is the language that ships; the other languages are drafts, so they are
/// checked only for what must hold in every language.
@Suite("Companion wording")
struct CopyCompanionWordingTests {
    static func english(_ key: PreviewStrings.Key) -> String {
        PreviewStrings.text(key, languagePreferences: ["en"])
    }

    // MARK: Developer Mode (review finding 23)

    @Test func developerModeNamesEverythingItEnables() {
        let subtitle = Self.english(.developerModeSubtitle)
        // The switch reveals the Try Preview page (⌘5) and the Open File command (⌘O), not only a sidebar row.
        for fragment in ["Try Preview", "Open File", "⌘O", "⌘5"] {
            #expect(subtitle.contains(fragment), "Developer Mode subtitle must name \(fragment): \(subtitle)")
        }
    }
}
