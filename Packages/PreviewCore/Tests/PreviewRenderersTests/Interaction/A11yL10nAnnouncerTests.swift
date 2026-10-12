import AppKit
import Foundation
import Testing
@testable import PreviewRenderers

/// Records what a `PreviewAnnouncer` was asked to say, without speaking it. One recorder per test. The owners of the
/// chrome, table, outline, 3D and mode code can use it to assert that an action was announced exactly once.
@MainActor
final class A11yAnnouncementRecorder {
    /// A notification the announcer's default path would have posted.
    struct Posted {
        let element: NSView
        let notification: NSAccessibility.Notification
        let userInfo: [NSAccessibility.NotificationUserInfoKey: Any]
    }

    private(set) var texts: [String] = []
    private(set) var posts: [Posted] = []

    /// Routes the announcer's text here; nothing is posted.
    func record(_ announcer: PreviewAnnouncer) {
        announcer.handler = { [weak self] text in self?.texts.append(text) }
    }

    /// Lets the announcer take its default path, but captures the notification instead of posting it.
    func capturePosts(of announcer: PreviewAnnouncer) {
        announcer.notificationHandler = { [weak self] element, notification, userInfo in
            self?.posts.append(Posted(element: element, notification: notification, userInfo: userInfo))
        }
    }
}

@Suite("Announcer: one owner and one policy for what the preview says aloud")
@MainActor
struct A11yL10nAnnouncerTests {
    @Test func aHandlerReceivesTheTextOnceAndNothingIsPosted() {
        let announcer = PreviewAnnouncer()
        let recorder = A11yAnnouncementRecorder()
        recorder.record(announcer)
        recorder.capturePosts(of: announcer)
        announcer.announce("3 of 120 rows", from: NSView())
        #expect(recorder.texts == ["3 of 120 rows"])
        #expect(recorder.posts.isEmpty, "A handler replaces speaking, so nothing reaches VoiceOver")
    }

    @Test func theDefaultPathPostsAnAnnouncementRequestFromTheNamedElementWithHighPriority() throws {
        let announcer = PreviewAnnouncer()
        let recorder = A11yAnnouncementRecorder()
        recorder.capturePosts(of: announcer)
        let element = NSView()
        announcer.announce("Concealed text copied.", from: element)
        #expect(recorder.posts.count == 1)
        let post = try #require(recorder.posts.first)
        #expect(post.element === element)
        #expect(post.notification == .announcementRequested)
        #expect(post.userInfo[.announcement] as? String == "Concealed text copied.")
        #expect(post.userInfo[.priority] as? Int == NSAccessibilityPriorityLevel.high.rawValue)
        #expect(recorder.texts.isEmpty)
    }

    @Test func theRequestedPriorityReachesTheNotification() {
        let announcer = PreviewAnnouncer()
        let recorder = A11yAnnouncementRecorder()
        recorder.capturePosts(of: announcer)
        let element = NSView()
        let priorities: [NSAccessibilityPriorityLevel] = [.low, .medium, .high]
        for priority in priorities { announcer.announce("Matches: 4", from: element, priority: priority) }
        let posted = recorder.posts.compactMap { $0.userInfo[.priority] as? Int }
        #expect(posted == priorities.map { $0.rawValue })
    }

    @Test func theNotificationPayloadCarriesTheTextAndThePriorityOnly() {
        let info = PreviewAnnouncer.userInfo(for: "No matches", priority: .medium)
        #expect(info.count == 2)
        #expect(info[.announcement] as? String == "No matches")
        #expect(info[.priority] as? Int == NSAccessibilityPriorityLevel.medium.rawValue)
    }

    @Test func emptyAndWhitespaceOnlyTextIsNeverAnnounced() {
        let announcer = PreviewAnnouncer()
        let recorder = A11yAnnouncementRecorder()
        recorder.capturePosts(of: announcer)
        let element = NSView()
        for text in ["", " ", "\n", " \t\r\n ", "\u{2003}"] { announcer.announce(text, from: element) }
        #expect(recorder.posts.isEmpty, "Nothing is posted for text with no words")
        recorder.record(announcer)
        for text in ["", "  ", "\n\n"] { announcer.announce(text, from: element) }
        #expect(recorder.texts.isEmpty)
    }

    @Test func repeatedActionsAreRepeatedAnnouncementsInOrder() {
        let announcer = PreviewAnnouncer()
        let recorder = A11yAnnouncementRecorder()
        recorder.record(announcer)
        let element = NSView()
        announcer.announce("Copied", from: element)
        announcer.announce("Matches: 2", from: element)
        announcer.announce("Copied", from: element)
        #expect(recorder.texts == ["Copied", "Matches: 2", "Copied"], "A second copy is announced again")
    }

    @Test func theTextIsDeliveredExactlyAsGiven() {
        let announcer = PreviewAnnouncer()
        let recorder = A11yAnnouncementRecorder()
        recorder.record(announcer)
        // A decomposed o-umlaut, an eszett, Arabic letters and an emoji, with surrounding spaces: canonical
        // equivalence must not hide a changed spelling, and nothing is trimmed.
        let text = "  Sorted by Gro\u{308}\u{DF}e, \u{627}\u{644}\u{627}\u{633}\u{645}, \u{1F642}  "
        announcer.announce(text, from: NSView())
        #expect(recorder.texts.count == 1)
        #expect(recorder.texts.first?.unicodeScalars.elementsEqual(text.unicodeScalars) == true)
    }

    @Test func aNewAnnouncerHasNoHandlersSoItSpeaksByDefault() {
        let announcer = PreviewAnnouncer()
        let replacesSpeaking = announcer.handler != nil || announcer.notificationHandler != nil
        #expect(!replacesSpeaking)
    }
}
