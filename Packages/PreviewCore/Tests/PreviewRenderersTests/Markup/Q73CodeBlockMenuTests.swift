import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q73 native code context menu", .serialized)
@MainActor
struct Q73CodeBlockMenuTests {
    private let english = Locale(identifier: "en_US")
    private let tags = "\u{E0061}\u{E0062}\u{E007F}"
    private let flag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
    nonisolated static let titleCases = [
        ("en", "Copy Code Block"), ("tr", "Kod bloğunu kopyala"), ("de", "Codeblock kopieren"),
        ("fr", "Copier le bloc de code"), ("zh-Hans", "复制代码块"), ("ja", "コードブロックをコピー"),
        ("hi", "कोड ब्लॉक कॉपी करें"), ("ku-Latn", "Bloka kodê kopî bike"), ("ru", "Копировать блок кода"),
        ("id", "Salin blok kode"), ("bn", "কোড ব্লক কপি করুন"), ("ha", "Kwafi tubalin lamba"),
        ("pt", "Copiar bloco de código"), ("es", "Copiar bloque de código")
    ]

    @Test func actualMenuOffersAnActionOnlyForAnExplicitCurrentRenderedBody() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let body = "😀 cafe\u{301} ••••\n\nlast"
        show(presentation(body), in: host)
        let range = try bodyRange(body, in: host)
        host.textView.setSelectedRange(NSRange(location: 0, length: 6))
        let selection = host.textView.selectedRanges
        for index in [range.location, range.location + 1, NSMaxRange(range) - 1] {
            let items = try codeItems(at: index, in: host)
            try #require(items.count == 1)
            #expect(items[0].keyEquivalent.isEmpty)
            let action = try #require(items[0].representedObject as? PreviewCommandAction)
            #expect(items[0].target === action)
            action.run(items[0])
            #expect((host.pasteboard.string(forType: .string) ?? "").utf16.elementsEqual(body.utf16))
            #expect(host.textView.selectedRanges == selection)
        }
        #expect(host.announcements.texts == Array(repeating: PreviewStrings.text(.chipCopied), count: 3))
        let inline = (host.textView.string as NSString).range(of: "inline").location
        for index in [-1, NSNotFound, 0, inline, NSMaxRange(range)] {
            #expect(try codeItems(at: index, in: host).isEmpty)
            #expect(host.view.codeBlockCopyMenuItem(at: index) == nil)
        }
        try select(.source, in: host)
        #expect(try codeItems(at: range.location, in: host).isEmpty)
    }

    @Test func retainedActualItemRejectsIdenticalReplacementBeforeWriting() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let value = presentation("same e\u{301} 😀")
        show(value, in: host)
        let index = try bodyRange("same e\u{301} 😀", in: host).location
        let old = try #require(host.view.codeBlockCopyMenuItem(at: index))
        let action = try #require(old.representedObject as? PreviewCommandAction)
        show(value, in: host, resetsContentState: true)
        host.pasteboard.setString("previous", forType: .string)
        var writes = 0
        host.view.plainTextCopyWriter = { text, board in writes += 1; return board.setString(text, forType: .string) }
        action.run(old)
        #expect(writes == 0 && host.pasteboard.string(forType: .string) == "previous" && host.announcements.texts.isEmpty)
        let current = try #require(host.view.codeBlockCopyMenuItem(at: index))
        try #require(current.representedObject as? PreviewCommandAction).run(current)
        #expect(writes == 1 && host.pasteboard.string(forType: .string) == "same e\u{301} 😀")
        #expect(host.announcements.texts == [PreviewStrings.text(.chipCopied)])
    }

    @Test func retainedItemUsesCurrentFindingPolicyAndCannotKeepAnOldGate() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let body = "safe " + flag + tags
        show(presentation(body, findsTags: true), in: host)
        let index = try bodyRange(body, in: host).location
        let old = try #require(host.view.codeBlockCopyMenuItem(at: index))
        let action = try #require(old.representedObject as? PreviewCommandAction)
        action.run(old)
        #expect((host.pasteboard.string(forType: .string) ?? "").utf16.elementsEqual(("safe " + flag).utf16))
        show(presentation(body), in: host)
        host.pasteboard.setString("previous", forType: .string)
        let count = host.announcements.texts.count
        action.run(old)
        #expect(host.pasteboard.string(forType: .string) == "previous" && host.announcements.texts.count == count)
        let current = try #require(host.view.codeBlockCopyMenuItem(at: index))
        try #require(current.representedObject as? PreviewCommandAction).run(current)
        #expect((host.pasteboard.string(forType: .string) ?? "").utf16.elementsEqual(body.utf16))
        #expect(host.announcements.texts.last == PreviewStrings.text(.chipCopied))
    }

    @Test func failedMenuWriteHasNoSuccessFeedbackOrSelectionAndStorageMutation() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let body = "safe ••••\n\nend 😀"
        show(presentation(body), in: host)
        host.textView.setSelectedRange(NSRange(location: 0, length: 6))
        let selection = host.textView.selectedRanges, snapshot = host.textView.attributedString().copy() as! NSAttributedString
        host.pasteboard.setString("previous", forType: .string)
        var writes = 0
        host.view.plainTextCopyWriter = { text, board in
            #expect(board === host.pasteboard && text.utf16.elementsEqual(body.utf16)); writes += 1; return false
        }
        let item = try #require(host.view.codeBlockCopyMenuItem(at: bodyRange(body, in: host).location))
        try #require(item.representedObject as? PreviewCommandAction).run(item)
        #expect(writes == 1 && host.pasteboard.string(forType: .string) == "previous" && host.announcements.texts.isEmpty)
        #expect(host.textView.selectedRanges == selection && host.textView.textStorage?.isEqual(to: snapshot) == true)
    }

    @Test func menuTitlesAcceptOnlyFiniteCanonicalIDsAndNeverDisplayRawUnknownLabels() {
        for language in [nil, SourceLanguageID(rawValue: "js"), .init(rawValue: "\u{212A}otlin"),
                         .init(rawValue: "swift\u{E0061}"), .init(rawValue: "swift" + String(repeating: "x", count: 100))] {
            #expect(CodeBlockCopyMenuTitle.text(for: language, locale: english, languagePreferences: ["en"]) == "Copy Code Block")
        }
        #expect(CodeBlockCopyMenuTitle.text(for: .swift, locale: english, languagePreferences: ["en"]) == "Copy Code Block (swift)")
    }

    @Test(arguments: titleCases)
    func titlesResolveWithLanguageInterpolationInEveryAppLanguage(language: String, title: String) {
        let locale = Locale(identifier: language)
        #expect(CodeBlockCopyMenuTitle.text(for: nil, locale: locale, languagePreferences: [language]) == title)
        #expect(CodeBlockCopyMenuTitle.text(for: .swift, locale: locale, languagePreferences: [language]) == title + " (swift)")
    }

    private func presentation(_ body: String, findsTags: Bool = false) -> TextPresentation {
        let source = "before `inline`\n\n```swift\n" + body + "\n```\n\nafter"
        return .init(formatID: .markdown, text: source, lineCount: source.components(separatedBy: "\n").count,
                     byteCount: source.utf8.count, encoding: .utf8, redactionCount: 1, syntax: .markdown,
                     findings: findsTags ? [.init(kind: .hiddenUnicodeTags, count: 3)] : [])
    }

    private func show(_ value: TextPresentation, in host: InteractionHarness, resetsContentState: Bool = false) {
        host.view.display(.ready(value), locale: english, resetsContentState: resetsContentState)
        host.view.layoutSubtreeIfNeeded()
    }

    private func bodyRange(_ body: String, in host: InteractionHarness) throws -> NSRange {
        let range = (host.textView.string as NSString).range(of: body)
        try #require(range.location != NSNotFound && range.length > 0)
        return range
    }

    private func codeItems(at index: Int, in host: InteractionHarness) throws -> [NSMenuItem] {
        let menu = try #require(host.view.textView(host.textView, menu: NSMenu(), for: host.keyEvent("", []), at: index))
        let title = CodeBlockCopyMenuTitle.text(for: .swift, locale: english)
        return menu.items.filter { !$0.isSeparatorItem && $0.title == title && $0.representedObject is PreviewCommandAction }
    }

    private func select(_ mode: NativePreviewMode, in host: InteractionHarness) throws {
        let index = try #require(host.view.displayedModes.firstIndex(of: mode))
        #expect(host.view.selectMode(number: index + 1)); host.view.layoutSubtreeIfNeeded()
    }
}
