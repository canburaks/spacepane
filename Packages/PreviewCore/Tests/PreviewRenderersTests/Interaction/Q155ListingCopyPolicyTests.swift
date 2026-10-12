import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q155 listing findings activate native copy hygiene", .serialized)
@MainActor
struct Q155ListingCopyPolicyTests {
    @Test(arguments: [FormatID.folder, .tar])
    func detectedTagNamesAreSanitizedWithoutMutatingTheSummary(format: FormatID) throws {
        let tags = "\u{E0061}\u{E0062}\u{E007F}"
        let flag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        let name = "safe" + flag + tags + ".txt"
        let text = "{\"listedEntries\":1,\"partial\":false,\"entries\":[{\"path\":\"" + name + "\",\"type\":\"file\",\"bytes\":1}]}"
        let presentation = TextPresentation(formatID: format, text: text, lineCount: 1,
            byteCount: text.utf8.count, encoding: .utf8, redactionCount: 0, syntax: .json,
            findings: [.init(kind: .listingHiddenCharacters, count: 1)], origin: .summary)
        let host = InteractionHarness()
        defer { host.release() }
        host.view.display(.ready(presentation), locale: Locale(identifier: "en"))
        #expect(host.view.copyAllSafeText())
        let expected = text.replacingOccurrences(of: tags, with: "")
        #expect(Array((host.pasteboard.string(forType: .string) ?? "").utf16) == Array(expected.utf16))
        #expect(host.announcements.texts == [PreviewStrings.text(.chipCopiedTagsRemoved)])
        #expect(Array((host.view.safePresentation?.text ?? "").utf16) == Array(text.utf16))
        // The native Source selection must receive the same live policy, not only Copy All.
        #expect(host.press("1", [.command, .option]))
        host.view.textView.setSelectedRange(NSRange(location: 0, length: host.view.textView.string.utf16.count))
        host.view.textView.copy(nil)
        #expect(Array((host.pasteboard.string(forType: .string) ?? "").utf16) == Array(expected.utf16))
        #expect(host.announcements.texts.filter { $0 == PreviewStrings.text(.chipCopiedTagsRemoved) }.count == 2)
    }
}
