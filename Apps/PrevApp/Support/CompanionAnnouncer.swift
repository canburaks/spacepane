import SwiftUI

/// The one place the companion speaks to VoiceOver outside a control: a short sentence about the result of
/// something the user just did (an undoable action, an undo, a redo, a refused import or drop, a finished scan, a
/// failed save). It follows the preview's announcer policy: one sentence per result, the same sentence twice when
/// the action happens twice, and never file content or anything made from it. Empty or whitespace-only text is
/// never announced.
/// This is the repository's first use of the SwiftUI announcement API, so it stays behind this one function.
@MainActor
enum CompanionAnnouncer {
    static func announce(_ text: String) {
        guard !text.unicodeScalars.allSatisfy({ $0.properties.isWhitespace }) else { return }
        AccessibilityNotification.Announcement(text).post()
    }
}
