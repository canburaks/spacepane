import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q73 current native code-body copy", .serialized)
@MainActor
struct Q73NativeCodeBlockCopyTests {
    private let english = Locale(identifier: "en_US")
    private let tags = "\u{E0061}\u{E0062}\u{E007F}"
    private let flag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"

    @Test func exactConcealedBodyCopyUsesThePrivateWriterAndPreservesSelectionAndStorage() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let body = "\n  •••• e\u{301} 😀 " + flag + "\n\n" + tags + " end\n"
        let prepared = "\n  •••• e\u{301} 😀 " + flag + "\n\n end\n"
        let presentation = codePresentation(body, findsTags: true)
        show(presentation, in: host)
        host.textView.setSelectedRange(NSRange(location: 0, length: 6))
        let selection = host.textView.selectedRanges
        let snapshot = host.textView.attributedString().copy() as! NSAttributedString
        let target = try target(for: body, in: host)
        #expect(target.block.language == .swift)
        #expect(host.view.copyCodeBlock(target))
        #expect(Array((host.pasteboard.string(forType: .string) ?? "").utf16) == Array(prepared.utf16))
        #expect(host.announcements.texts == [PreviewStrings.text(.chipCopiedTagsRemoved)])
        #expect(host.textView.selectedRanges == selection && host.textView.textStorage?.isEqual(to: snapshot) == true)
        #expect(presentation.text.utf16.elementsEqual(codeSource(body).utf16))
    }

    @Test func retainedActionRejectsAnIdenticalReplacementGenerationBeforeWriting() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let presentation = codePresentation("same e\u{301} 😀")
        show(presentation, in: host)
        let old = try target(for: "same e\u{301} 😀", in: host)
        let retained: @MainActor () -> Bool = { host.view.copyCodeBlock(old) }
        show(presentation, in: host, resetsContentState: true)
        var writes = 0
        host.pasteboard.setString("previous", forType: .string)
        host.view.plainTextCopyWriter = { text, board in
            writes += 1
            #expect(board === host.pasteboard && text == "same e\u{301} 😀")
            return board.setString(text, forType: .string)
        }
        #expect(!retained())
        #expect(writes == 0 && host.pasteboard.string(forType: .string) == "previous")
        #expect(host.announcements.texts.isEmpty)
        #expect(host.view.copyCodeBlock(try target(for: "same e\u{301} 😀", in: host)))
        #expect(writes == 1 && host.announcements.texts == [PreviewStrings.text(.chipCopied)])
    }

    @Test func canonicallyEqualSameLengthReplacementInvalidatesTheOldBodyAndKeepsNewCodeUnits() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let oldBody = "e\u{301}\u{323} 😀", newBody = "e\u{323}\u{301} 😀"
        #expect(oldBody == newBody && oldBody.utf16.count == newBody.utf16.count)
        #expect(!oldBody.utf16.elementsEqual(newBody.utf16))
        show(codePresentation(oldBody), in: host)
        let old = try target(for: oldBody, in: host)
        show(codePresentation(newBody), in: host)
        host.pasteboard.setString("previous", forType: .string)
        #expect(!host.view.copyCodeBlock(old) && host.pasteboard.string(forType: .string) == "previous")
        #expect(host.view.copyCodeBlock(try target(for: newBody, in: host)))
        #expect(Array((host.pasteboard.string(forType: .string) ?? "").utf16) == Array(newBody.utf16))
    }

    @Test func identicalTextFindingGateChangesRejectOldActionsAndApplyTheCurrentPolicy() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let body = "safe " + flag + tags
        show(codePresentation(body, findsTags: true), in: host)
        let old = try target(for: body, in: host)
        #expect(host.view.copyCodeBlock(old))
        #expect(Array((host.pasteboard.string(forType: .string) ?? "").utf16) == Array(("safe " + flag).utf16))
        show(codePresentation(body, findsTags: false), in: host)
        host.textView.setSelectedRange(NSRange(location: 0, length: 4))
        let selection = host.textView.selectedRanges
        let count = host.announcements.texts.count
        host.pasteboard.setString("previous", forType: .string)
        #expect(!host.view.copyCodeBlock(old) && host.pasteboard.string(forType: .string) == "previous")
        #expect(host.announcements.texts.count == count)
        #expect(host.view.copyCodeBlock(try target(for: body, in: host)))
        #expect(Array((host.pasteboard.string(forType: .string) ?? "").utf16) == Array(body.utf16))
        #expect(host.announcements.texts.last == PreviewStrings.text(.chipCopied))
        #expect(host.textView.selectedRanges == selection)
    }

    @Test func aFailedPrivateWriterHasNoSuccessFeedbackOrSelectionMutation() throws {
        let host = InteractionHarness()
        defer { host.release() }
        show(codePresentation("safe •••• 😀"), in: host)
        host.textView.setSelectedRange(NSRange(location: 0, length: 3))
        let selection = host.textView.selectedRanges
        host.pasteboard.setString("previous", forType: .string)
        var writes = 0
        host.view.plainTextCopyWriter = { text, board in
            writes += 1
            #expect(board === host.pasteboard && text == "safe •••• 😀")
            return false
        }
        #expect(!host.view.copyCodeBlock(try target(for: "safe •••• 😀", in: host)))
        #expect(writes == 1 && host.announcements.texts.isEmpty)
        #expect(host.pasteboard.string(forType: .string) == "previous" && host.textView.selectedRanges == selection)
    }

    @Test func appearanceOnlyRestylingPreservesTheCurrentTargetAndSelection() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let body = "  cafe\u{301} 😀\n\nlast"
        let presentation = codePresentation(body)
        show(presentation, in: host)
        let target = try target(for: body, in: host)
        host.textView.setSelectedRange(NSRange(location: 0, length: 4))
        let selection = host.textView.selectedRanges
        host.view.display(.ready(presentation), typography: .init(fontSize: 26, fontFamily: "Menlo"),
                          theme: .dark, syntaxStyle: .init(usesColor: false), locale: english)
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.copyCodeBlock(target))
        #expect(Array((host.pasteboard.string(forType: .string) ?? "").utf16) == Array(body.utf16))
        #expect(host.textView.selectedRanges == selection)
    }

    @Test func modeExitReturnStateClearAndSuspendResumeCannotReviveRetainedActions() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let presentation = codePresentation("current")
        show(presentation, in: host)
        let beforeMode = try target(for: "current", in: host)
        try select(.source, in: host)
        #expect(host.view.codeBlockCopyTarget(at: 0) == nil)
        try select(.rendered, in: host)
        let modeCount = host.announcements.texts.count
        #expect(!host.view.copyCodeBlock(beforeMode) && host.announcements.texts.count == modeCount)
        let beforeSuspend = try target(for: "current", in: host)
        host.view.suspendResources()
        #expect(!host.view.copyCodeBlock(beforeSuspend) && host.view.codeBlockCopyTarget(at: 0) == nil)
        host.view.resumeResources()
        #expect(!host.view.copyCodeBlock(beforeSuspend))
        let beforeClear = try target(for: "current", in: host)
        host.view.display(.unavailable(.missingFile), locale: english)
        let stateCount = host.announcements.texts.count
        #expect(!host.view.copyCodeBlock(beforeClear) && host.announcements.texts.count == stateCount)
        show(presentation, in: host)
        #expect(!host.view.copyCodeBlock(beforeClear))
        #expect(host.view.copyCodeBlock(try target(for: "current", in: host)))
    }

    @Test func onlyExplicitPositiveBodiesAreTargetsAndMalformedTargetsNeverWrite() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let source = "prose `inline`\n\n```swift\n😀 body\n```\nafter"
        show(plainPresentation(source, format: .markdown, syntax: .markdown), in: host)
        #expect(host.view.codeBlockCopyTarget(at: -1) == nil && host.view.codeBlockCopyTarget(at: NSNotFound) == nil)
        #expect(host.view.codeBlockCopyTarget(at: 0) == nil)
        #expect(host.view.codeBlockCopyTarget(at: (host.textView.string as NSString).range(of: "inline").location) == nil)
        let body = (host.textView.string as NSString).range(of: "😀 body")
        #expect(host.view.codeBlockCopyTarget(at: NSMaxRange(body)) == nil)
        // A native index inside a supplementary scalar identifies the complete body, never a split selection.
        let good = try #require(host.view.codeBlockCopyTarget(at: body.location + 1))
        #expect(good.block.range == body)
        let bad = CodeBlockCopyTarget(revision: good.revision,
            block: .init(range: NSRange(location: NSNotFound, length: Int.max), language: nil))
        var writes = 0
        host.view.plainTextCopyWriter = { _, _ in writes += 1; return true }
        #expect(!host.view.copyCodeBlock(bad) && writes == 0)
        show(plainPresentation("```\n\n```", format: .markdown, syntax: .markdown), in: host)
        #expect(host.view.codeBlockCopyTarget(at: 0) == nil)
        show(plainPresentation("```\n\n\n```", format: .markdown, syntax: .markdown), in: host)
        let blank = try #require(host.view.codeBlockCopyTarget(at: 0))
        host.view.plainTextCopyWriter = { text, board in board.setString(text, forType: .string) }
        #expect(host.view.copyCodeBlock(blank) && host.pasteboard.string(forType: .string) == "\n")
    }

    private func codeSource(_ body: String) -> String { "before\n\n```swift\n" + body + "\n```\n\nafter" }

    private func codePresentation(_ body: String, findsTags: Bool = false) -> TextPresentation {
        let source = codeSource(body)
        return .init(formatID: .markdown, text: source, lineCount: source.components(separatedBy: "\n").count,
                     byteCount: source.utf8.count, encoding: .utf8, redactionCount: 1, syntax: .markdown,
                     findings: findsTags ? [.init(kind: .hiddenUnicodeTags, count: 3)] : [])
    }

    private func show(_ presentation: TextPresentation, in host: InteractionHarness, resetsContentState: Bool = false) {
        host.view.display(.ready(presentation), locale: english, resetsContentState: resetsContentState)
        host.view.layoutSubtreeIfNeeded()
    }

    private func target(for body: String, in host: InteractionHarness) throws -> CodeBlockCopyTarget {
        let range = (host.textView.string as NSString).range(of: body)
        try #require(range.location != NSNotFound)
        return try #require(host.view.codeBlockCopyTarget(at: range.location))
    }

    private func select(_ mode: NativePreviewMode, in host: InteractionHarness) throws {
        let index = try #require(host.view.displayedModes.firstIndex(of: mode))
        #expect(host.view.selectMode(number: index + 1))
        host.view.layoutSubtreeIfNeeded()
    }
}
