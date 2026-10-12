import AppKit

/// The one owner of what a preview says aloud. Every spoken result goes through `announce`, so the policy below lives
/// in one place and tests record announcements instead of listening for them (decision 027, Q-36; accessibility
/// review AL4 and R5). A preview owns one announcer and hands it to the views it hosts, so one handler replaces all
/// of its speech in a test.
///
/// How it speaks: by default a VoiceOver announcement (`NSAccessibility.post` with `.announcementRequested`) posted
/// from the element the caller names. Whether VoiceOver hears an announcement posted from the Quick Look extension
/// process, and which element makes it audible there, has not been observed on a Mac, so the policy is the design and
/// not a verified behavior. The companion's SwiftUI views speak through `AccessibilityNotification.Announcement`
/// under the same policy.
///
/// Policy
/// - One announcement per user action or state change, from the view the action happened in. Two identical actions are
///   two announcements: the announcer never collapses repeats.
/// - Announce: a non-content state (unavailable, disabled, settings unavailable: its title and body; loading only after
///   the spinner delay); a mode switch made from the keyboard or a link, as the new mode's title; a copy ("Copied",
///   one string for every copy path); a filter result with its count, zero included, and a sort result; Go to Line; a
///   zoom step, as the new level; a 3D view preset; and a command that is not available where the user tried it.
/// - Never announce file content, or anything made from it that has not been concealed: only app-written sentences,
///   counts and text that is already concealed and on screen (a column title in a sort result is shown text).
/// - Never announce a live reload, a restyle, a resize or an appearance change. A reload that turns the preview into a
///   non-content state announces that state once, like any state change.
/// - Empty or whitespace-only text is never announced.
/// - Priority: `.high`, the default, for the result of something the user just did. `.medium` for a result that updates
///   while the user is still typing, such as a live filter count, so it queues behind the characters being echoed.
@MainActor
final class PreviewAnnouncer {
    /// Receives each announcement instead of speaking it; tests record here. Nil, the default, speaks.
    var handler: ((String) -> Void)?

    /// Receives the accessibility notification the default path would post, with the element it would post from,
    /// instead of posting it. Tests use it to check the notification and its payload; `handler` takes precedence
    /// for spoken announcements only, leaving structural notifications independent of speech.
    var notificationHandler: ((NSView, NSAccessibility.Notification, [NSAccessibility.NotificationUserInfoKey: Any]) -> Void)?

    /// Says `text` once, unless it is empty or only whitespace. `view` is the element the announcement is posted from:
    /// the view the user acted in. The text is delivered exactly as given.
    func announce(_ text: String, from view: NSView, priority: NSAccessibilityPriorityLevel = .high) {
        guard !text.unicodeScalars.allSatisfy({ $0.properties.isWhitespace }) else { return }
        if let handler { handler(text); return }
        let payload = Self.userInfo(for: text, priority: priority)
        if let notificationHandler { notificationHandler(view, .announcementRequested, payload); return }
        NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: payload)
    }

    /// The visible hierarchy has changed. The owner publishes only after installing the replacement, and keeps
    /// repeats, appearance changes and an unrevealed loading grace period quiet. No source values enter a payload.
    func layoutChanged(from view: NSView) {
        if let notificationHandler { notificationHandler(view, .layoutChanged, [:]); return }
        NSAccessibility.post(element: view, notification: .layoutChanged)
    }

    /// The notification payload: the text and its priority, nothing else.
    static func userInfo(for text: String, priority: NSAccessibilityPriorityLevel) -> [NSAccessibility.NotificationUserInfoKey: Any] {
        [.announcement: text, .priority: priority.rawValue]
    }
}
