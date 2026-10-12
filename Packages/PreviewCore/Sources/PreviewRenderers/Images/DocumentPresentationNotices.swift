import Foundation
import PreviewContracts

/// Facts an ebook or comic adapter leaves in its already-concealed presentation, and the localized status
/// lines derived from them. Adapters cannot localize, so they record only neutral flags:
/// front matter lines `drm: true` and `partial: true` on EPUB, FB2 and MHTML text, and the `pageCount`
/// field of a comic's JSON summary. Everything here is read from the safe text, never from a file. The
/// Rendered view reads the same text but hides these flags, because the status line already says the same
/// thing in the reader's language (see `MarkdownFrontMatterStyle`).
enum DocumentPresentationNotices {
    /// Formats whose safe text is Markdown with adapter-written front matter.
    static let documentFormats: Set<FormatID> = [.epub, .fictionBook, .webArchive]

    static func lines(for presentation: TextPresentation, locale: Locale) -> [String] {
        if documentFormats.contains(presentation.formatID) {
            let flags = FrontMatterFlags.parse(presentation.text)
            if flags.contains("drm") { return [PreviewStrings.text(.ebooksNoticeDRM)] }
            if flags.contains("partial") {
                // An e-book adapter that counted its chapters says how many are shown; any other partial
                // document keeps the general sentence.
                if let chapters = EbookChapterFacts.parse(presentation.text) {
                    let total = chapters.total.formatted(.number.locale(locale))
                    return [PreviewStrings.count(.ebooksNoticeChaptersShown, chapters.shown, additionalArguments: [total],
                                                 locale: locale)]
                }
                return [PreviewStrings.text(.ebooksNoticePartialText)]
            }
            return []
        }
        if presentation.formatID == .comicBook, let total = ComicPageFacts.pageCount(in: presentation),
           total > presentation.images.count, !presentation.images.isEmpty {
            let arguments: [CVarArg] = [presentation.images.count.formatted(.number.locale(locale)),
                                        total.formatted(.number.locale(locale))]
            return [PreviewStrings.format(.ebooksNoticePartialPages, arguments: arguments, locale: locale)]
        }
        return []
    }
}

/// The neutral field names that the ebook, FictionBook and web-archive adapters write in their front matter
/// (`MarkdownWriter.frontMatter`), each with the localized label the Rendered view shows in place of the raw key.
/// The raw values are the adapters' wire names and are never translated; the values stay the document's own.
enum DocumentFrontMatterField: String, CaseIterable, Sendable {
    case title, author, language, publisher, date, identifier, source, resources
    /// The adapters write the free-text blurb as `description`.
    case summary = "description"

    /// The label, with its colon, so each language sets its own punctuation.
    var label: PreviewStrings.Key {
        switch self {
        case .title: .documentFrontMatterTitle
        case .author: .documentFrontMatterAuthor
        case .language: .documentFrontMatterLanguage
        case .publisher: .documentFrontMatterPublisher
        case .date: .documentFrontMatterDate
        case .identifier: .documentFrontMatterIdentifier
        case .summary: .documentFrontMatterDescription
        case .source: .documentFrontMatterSource
        case .resources: .documentFrontMatterResources
        }
    }
}

/// Boolean flags in the leading `---` front matter block of generated Markdown. Only a bounded prefix is read.
enum FrontMatterFlags {
    static let maximumLines = 48

    /// Whether a front-matter entry is a machine flag (`partial: true`) rather than a descriptive field: a key
    /// that is not one of the adapters' fields, with the value `true`. A field whose own value reads `true`
    /// (a book titled "true") is still a field.
    static func isFlag(_ entry: FrontMatterEntry) -> Bool {
        // The chapter counts are machine facts like the flags: the status line states them in the reader's language.
        // A count key whose value is not a plain number is an ordinary entry and stays visible.
        if let key = entry.key, EbookChapterFacts.isCountKey(key) { return isCount(entry.value) }
        guard let key = entry.key, entry.value == "true" else { return false }
        return DocumentFrontMatterField(rawValue: key) == nil
    }

    /// Whether a front-matter value is a plain non-negative whole number of at most seven digits.
    static func isCount(_ value: String) -> Bool {
        (1...7).contains(value.utf8.count) && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    /// Keys written as `key: true`.
    static func parse(_ text: String) -> Set<String> {
        var flags: Set<String> = []
        var lines = text.prefix(8_192).split(separator: "\n", maxSplits: maximumLines, omittingEmptySubsequences: false).makeIterator()
        guard lines.next() == "---" else { return flags }
        var seen = 0
        while let line = lines.next(), seen < maximumLines {
            seen += 1
            if line == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            if line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces) == "true" {
                flags.insert(String(line[..<colon]))
            }
        }
        return flags
    }
}

extension FrontMatterFlags {
    /// Entries written as `key: 12` in the leading block, under the same bounds as `parse`. A value that is not a
    /// plain number is not a count. Later lines win over earlier ones, as in a YAML mapping read by `parse`.
    static func counts(in text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        var lines = text.prefix(8_192).split(separator: "\n", maxSplits: maximumLines, omittingEmptySubsequences: false).makeIterator()
        guard lines.next() == "---" else { return counts }
        var seen = 0
        while let line = lines.next(), seen < maximumLines {
            seen += 1
            if line == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if isCount(value), let number = Int(value) { counts[String(line[..<colon])] = number }
        }
        return counts
    }
}

/// How many chapters of an e-book are shown, as the EPUB adapter measured them and wrote them beside its `partial`
/// flag (`chaptersShown: 12`, `chaptersTotal: 38`). The renderer only reads these two numbers from the leading
/// front matter of the already-concealed text; it never counts headings or chapters itself. The adapter writes them
/// only when some chapter is not represented, and the last chapter shown may be cut short.
struct EbookChapterFacts: Equatable, Sendable {
    static let shownKey = "chaptersShown"
    static let totalKey = "chaptersTotal"
    /// Largest chapter count taken at face value; a larger one is not a number an e-book honestly has.
    static let maximumTotal = 1_000_000

    let shown: Int
    let total: Int

    static func isCountKey(_ key: String) -> Bool { key == shownKey || key == totalKey }

    /// The counts, or nil unless both are present and fewer chapters are shown than the book has.
    static func parse(_ text: String) -> EbookChapterFacts? {
        let counts = FrontMatterFlags.counts(in: text)
        guard let shown = counts[shownKey], let total = counts[totalKey],
              (1...maximumTotal).contains(total), (0..<total).contains(shown) else { return nil }
        return EbookChapterFacts(shown: shown, total: total)
    }
}

/// The page count a comic's concealed JSON summary reports for the whole archive.
enum ComicPageFacts {
    static let maximumTextBytes = 65_536

    static func pageCount(in presentation: TextPresentation) -> Int? {
        guard presentation.formatID == .comicBook, presentation.syntax == .json,
              presentation.text.utf8.count <= maximumTextBytes,
              let object = try? JSONSerialization.jsonObject(with: Data(presentation.text.utf8)) as? [String: Any],
              let count = (object["pageCount"] as? NSNumber)?.intValue, (0...1_000_000).contains(count) else { return nil }
        return count
    }
}
