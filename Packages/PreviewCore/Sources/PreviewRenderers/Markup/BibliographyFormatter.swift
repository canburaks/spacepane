import Foundation

/// The citation styles a reference list can be shown in. The rules are simplified renditions
/// of each style guide for the common entry types; they are a reading aid, not a substitute
/// for the guide. Titles are used as written, because a program cannot know which words a
/// style would lowercase. The terms the styles print ("et al.", "n.d.", "(Ed.)", "pp.", thesis and
/// report labels, edition ordinals) are the style guides' own English terms in every interface
/// language, by decision (015, amended 2026-10-06); the References notice says so and they are
/// deliberately not localized.
enum BibliographyStyle: String, CaseIterable, Sendable {
    case apa, mla, chicago, ieee

    var title: PreviewStrings.Key {
        switch self {
        case .apa: .markupStyleAPA
        case .mla: .markupStyleMLA
        case .chicago: .markupStyleChicago
        case .ieee: .markupStyleIEEE
        }
    }
}

/// One formatted reference: its text and the ranges (UTF-16, relative to the text) set in italics.
struct FormattedReference: Equatable, Sendable {
    let text: String
    let italics: [NSRange]
}

enum BibliographyFormatter {
    // MARK: Document

    /// The whole list as a decorated document. APA, MLA and Chicago sort by first author, then year
    /// and title; IEEE keeps the file order and numbers the entries. Every entry is one paragraph
    /// with a hanging indent, and each is collected as a heading (its citation key) for navigation.
    static func document(_ bibliography: SafeBibliography, style: BibliographyStyle) -> SafeMarkdownDocument? {
        var builder = MarkupBuilder()
        for (position, item) in ordered(bibliography, style: style).enumerated() {
            if position > 0 { builder.newline(); builder.newline() }
            let start = builder.length
            let prefix = style == .ieee ? "[\(position + 1)] " : ""
            builder.append(prefix)
            let textStart = builder.length
            builder.append(item.reference.text)
            for range in item.reference.italics {
                builder.decorate(.italic, range: NSRange(location: textStart + range.location, length: range.length))
            }
            builder.decorate(.listItem(depth: 0, markerLength: style == .ieee ? max(prefix.count, 4) : 3), from: start)
            builder.addHeading(level: 1, title: item.key, range: NSRange(location: start, length: builder.length - start))
            if builder.isOverflowed { return nil }
        }
        return builder.finish()
    }

    struct Item {
        let key: String
        let reference: FormattedReference
    }

    static func ordered(_ bibliography: SafeBibliography, style: BibliographyStyle) -> [Item] {
        let formatted = bibliography.entries.map { entry in
            (entry: entry, reference: format(entry, style: style), sort: sortKey(entry))
        }
        let sorted = style == .ieee ? formatted : formatted.sorted { $0.sort.lexicographicallyPrecedes($1.sort) }
        return sorted.map { Item(key: $0.entry.key, reference: $0.reference) }
    }

    /// Sort key: first creator's family name, then year, then title.
    private static func sortKey(_ entry: BibliographyEntry) -> [String] {
        let creator = entry.people("author").first ?? entry.people("editor").first
        let name = creator.map { $0.surname + " " + $0.first } ?? (entry.field("title") ?? entry.key)
        func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        return [fold(name), entry.field("year") ?? entry.field("date") ?? "", fold(entry.field("title") ?? "")]
    }

    static func format(_ entry: BibliographyEntry, style: BibliographyStyle) -> FormattedReference {
        let fields = ReferenceFields(entry)
        switch style {
        case .apa: return APA.format(fields)
        case .mla: return MLA.format(fields)
        case .chicago: return Chicago.format(fields)
        case .ieee: return IEEE.format(fields)
        }
    }
}

// MARK: Shared pieces

enum ReferenceKind {
    case article, book, proceedings, chapter, thesis, report, other

    init(type: String) {
        switch type {
        case "article": self = .article
        case "book", "booklet", "manual", "proceedings": self = .book
        case "inproceedings", "conference": self = .proceedings
        case "incollection", "inbook": self = .chapter
        case "phdthesis", "mastersthesis", "thesis": self = .thesis
        case "techreport", "report": self = .report
        default: self = .other
        }
    }
}

/// Plain-text field access with the aliases BibTeX and BibLaTeX files use.
struct ReferenceFields {
    let entry: BibliographyEntry
    let kind: ReferenceKind

    init(_ entry: BibliographyEntry) {
        self.entry = entry
        kind = ReferenceKind(type: entry.type)
    }

    var authors: [BibliographyName] { entry.people("author") }
    var editors: [BibliographyName] { entry.people("editor") }
    var title: String? { entry.field("title") }
    var bookTitle: String? { entry.field("booktitle") }
    var journal: String? { entry.field("journal", "journaltitle") }
    var volume: String? { entry.field("volume") }
    var number: String? { entry.field("number", "issue") }
    var pages: String? { entry.field("pages") }
    var publisher: String? { entry.field("publisher") }
    var address: String? { entry.field("address", "location") }
    var edition: String? { entry.field("edition") }
    var institution: String? { entry.field("institution", "school", "organization") }
    var howPublished: String? { entry.field("howpublished") }
    var month: String? { entry.field("month") }
    var year: String? {
        if let year = entry.field("year") { return year }
        if let date = entry.field("date") { return String(date.prefix(4)) }
        return nil
    }
    var doi: String? { entry.field("doi") }
    var url: String? { entry.field("url") }

    /// A DOI as a link when it is not one already; plain text, never opened.
    var doiLink: String? {
        guard let doi else { return nil }
        return doi.lowercased().hasPrefix("http") ? doi : "https://doi.org/" + doi
    }

    /// Month as a number 1...12, from a name, abbreviation or digits.
    var monthNumber: Int? {
        guard let month else { return nil }
        if let number = Int(month), (1...12).contains(number) { return number }
        let names = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let prefix = String(month.lowercased().prefix(3))
        return names.firstIndex(of: prefix).map { $0 + 1 }
    }

    /// Page ranges with the dash a style prefers; a single page keeps its number.
    func pages(separator: String) -> String? {
        guard let pages else { return nil }
        let ranges = pages.replacingOccurrences(of: "—", with: "–").replacingOccurrences(of: "–", with: "-")
        let parts = ranges.split(separator: "-", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.joined(separator: separator)
    }
}

/// Builds one reference's text and its italic ranges.
struct ReferenceBuilder {
    private(set) var text = ""
    private(set) var italics: [NSRange] = []
    private var length = 0

    var isEmpty: Bool { text.isEmpty }

    mutating func plain(_ string: String) {
        guard !string.isEmpty else { return }
        text.append(string)
        length += string.utf16.count
    }

    mutating func italic(_ string: String) {
        guard !string.isEmpty else { return }
        italics.append(NSRange(location: length, length: string.utf16.count))
        plain(string)
    }

    mutating func space() { if !text.isEmpty, !text.hasSuffix(" ") { plain(" ") } }

    /// Ends the current part with `mark` unless it already ends in terminal punctuation.
    mutating func end(_ mark: String = ".") {
        guard !text.isEmpty else { return }
        // Punctuation inside closing quotation marks counts; punctuation inside parentheses does not.
        var tail = text
        while let last = tail.last, "\"”’*".contains(last) { tail.removeLast() }
        if let last = tail.last, ".?!".contains(last) { return }
        // A quoted title that ended with a comma (`“Title,”`) closes with a period instead.
        if text.hasSuffix(",”") {
            text.removeLast(2)
            length -= 2
            plain(".”")
            return
        }
        plain(mark)
    }

    /// Starts a new part: a separating space after the previous one.
    mutating func part(_ string: String, italic: Bool = false) {
        guard !string.isEmpty else { return }
        space()
        if italic { self.italic(string) } else { plain(string) }
    }

    func finish() -> FormattedReference { FormattedReference(text: text, italics: italics) }
}

/// Edition ordinals: "2" becomes "2nd" for styles that print "2nd ed.".
private func ordinal(_ value: String) -> String {
    guard let number = Int(value) else { return value }
    let suffix: String
    switch (number % 100, number % 10) {
    case (11...13, _): suffix = "th"
    case (_, 1): suffix = "st"
    case (_, 2): suffix = "nd"
    case (_, 3): suffix = "rd"
    default: suffix = "th"
    }
    return "\(number)\(suffix)"
}

// MARK: APA 7

enum APA {
    static func names(_ people: [BibliographyName]) -> String {
        let hasOthers = people.contains { $0.isOthers }
        let named = people.filter { !$0.isOthers }.map(formatted)
        guard !named.isEmpty else { return "" }
        let list: String
        switch named.count {
        case 1: list = named[0]
        case 2: list = hasOthers ? named.joined(separator: ", ") : named[0] + ", & " + named[1]
        case 3...20:
            list = hasOthers ? named.joined(separator: ", ") : named.dropLast().joined(separator: ", ") + ", & " + named[named.count - 1]
        default: list = named.prefix(19).joined(separator: ", ") + ", . . . " + named[named.count - 1]
        }
        return hasOthers ? list + ", et al." : list
    }

    private static func formatted(_ name: BibliographyName) -> String {
        var result = name.surname
        if !name.initials.isEmpty { result += ", " + name.initials }
        if !name.jr.isEmpty { result += ", " + name.jr }
        return result
    }

    static func format(_ fields: ReferenceFields) -> FormattedReference {
        var b = ReferenceBuilder()
        let authors = fields.authors
        let creators = authors.isEmpty ? fields.editors : authors
        let year = "(" + (fields.year ?? "n.d.") + ")."
        let isStandalone = fields.kind == .book || fields.kind == .report || fields.kind == .thesis || fields.kind == .other
        if !creators.isEmpty {
            var credit = names(creators)
            if authors.isEmpty { credit += creators.count > 1 ? " (Eds.)" : " (Ed.)" }
            b.plain(credit)
            b.end()
            b.part(year)
        } else if let title = fields.title {
            // Without an author the title takes its place, ahead of the date.
            if isStandalone { b.italic(title) } else { b.plain(title) }
            b.end()
            b.part(year)
        } else {
            b.plain(year)
        }
        let titleLead = creators.isEmpty && fields.title != nil
        switch fields.kind {
        case .article:
            if !titleLead, let title = fields.title { b.part(title); b.end() }
            if let journal = fields.journal {
                b.space(); b.italic(journal)
                if let volume = fields.volume {
                    b.plain(", "); b.italic(volume)
                    if let number = fields.number { b.plain("(\(number))") }
                } else if let number = fields.number { b.plain(", (\(number))") }
                if let pages = fields.pages(separator: "–") { b.plain(", " + pages) }
                b.end()
            } else if let pages = fields.pages(separator: "–") { b.part(pages); b.end() }
        case .proceedings, .chapter:
            if !titleLead, let title = fields.title { b.part(title); b.end() }
            if let book = fields.bookTitle {
                b.space(); b.plain("In ")
                let editors = authors.isEmpty ? [] : fields.editors
                if !editors.isEmpty {
                    let credit = editors.filter { !$0.isOthers }.map { ($0.initials.isEmpty ? "" : $0.initials + " ") + $0.surname }
                    b.plain(credit.joined(separator: ", ") + (editors.count > 1 ? " (Eds.), " : " (Ed.), "))
                }
                b.italic(book)
                var detail: [String] = []
                if let edition = fields.edition { detail.append(ordinal(edition) + " ed.") }
                if let pages = fields.pages(separator: "–") { detail.append("pp. " + pages) }
                if !detail.isEmpty { b.plain(" (" + detail.joined(separator: ", ") + ")") }
                b.end()
            }
            if let publisher = fields.publisher { b.part(publisher); b.end() }
        case .thesis:
            if !titleLead, let title = fields.title { b.part(title, italic: true) }
            let degree = fields.entry.type == "mastersthesis" ? "Master’s thesis" : "Doctoral dissertation"
            let school = fields.institution
            b.part("[" + degree + (school.map { ", " + $0 } ?? "") + "]")
            b.end()
        case .report:
            if !titleLead, let title = fields.title { b.part(title, italic: true) }
            if let number = fields.number { b.plain(" (Report No. \(number))") }
            b.end()
            if let institution = fields.institution { b.part(institution); b.end() }
        case .book, .other:
            if !titleLead, let title = fields.title { b.part(title, italic: true) }
            if let edition = fields.edition { b.plain(" (" + ordinal(edition) + " ed.)") }
            b.end()
            if let publisher = fields.publisher ?? fields.howPublished { b.part(publisher); b.end() }
        }
        if let link = fields.doiLink ?? fields.url { b.part(link) }
        return b.finish()
    }
}

// MARK: MLA 9

enum MLA {
    private static func inverted(_ name: BibliographyName) -> String {
        var result = name.surname
        if !name.first.isEmpty { result += ", " + name.first }
        if !name.jr.isEmpty { result += ", " + name.jr }
        return result
    }

    private static func direct(_ name: BibliographyName) -> String {
        [name.first, name.surname].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func names(_ people: [BibliographyName]) -> String {
        let hasOthers = people.contains { $0.isOthers }
        let named = people.filter { !$0.isOthers }
        guard let first = named.first else { return "" }
        if named.count >= 3 || (hasOthers && !named.isEmpty) { return inverted(first) + ", et al." }
        if named.count == 2 { return inverted(first) + ", and " + direct(named[1]) }
        return inverted(first)
    }

    static func format(_ fields: ReferenceFields) -> FormattedReference {
        var b = ReferenceBuilder()
        let authors = fields.authors
        let creators = authors.isEmpty ? fields.editors : authors
        if !creators.isEmpty {
            b.plain(names(creators) + (authors.isEmpty ? (creators.count > 1 ? ", editors" : ", editor") : ""))
            b.end()
        }
        let quoted = fields.kind == .article || fields.kind == .proceedings || fields.kind == .chapter
        if let title = fields.title {
            if quoted { b.part("“" + title + (title.last.map { ".?!".contains($0) } == true ? "" : ".") + "”") }
            else { b.part(title, italic: true); b.end() }
        }
        // The container and its locators, separated by commas and ended by a period.
        var container = ReferenceBuilder()
        switch fields.kind {
        case .article:
            if let journal = fields.journal { container.italic(journal) }
            for piece in [fields.volume.map { "vol. " + $0 }, fields.number.map { "no. " + $0 }, fields.year,
                          fields.pages(separator: "-").map { "pp. " + $0 }] {
                guard let piece else { continue }
                if !container.isEmpty { container.plain(", ") }
                container.plain(piece)
            }
        case .proceedings, .chapter:
            if let book = fields.bookTitle { container.italic(book) }
            let editors = fields.editors
            if !editors.isEmpty, !authors.isEmpty {
                if !container.isEmpty { container.plain(", ") }
                container.plain("edited by " + editors.filter { !$0.isOthers }.map(direct).joined(separator: " and "))
            }
            for piece in [fields.publisher, fields.year, fields.pages(separator: "-").map { "pp. " + $0 }] {
                guard let piece else { continue }
                if !container.isEmpty { container.plain(", ") }
                container.plain(piece)
            }
        default:
            var pieces: [String] = []
            if let edition = fields.edition { pieces.append(ordinal(edition) + " ed.") }
            if let publisher = fields.publisher ?? fields.institution ?? fields.howPublished { pieces.append(publisher) }
            if let year = fields.year { pieces.append(year) }
            container.plain(pieces.joined(separator: ", "))
        }
        let built = container.finish()
        if !built.text.isEmpty {
            b.space()
            let offset = b.text.utf16.count
            b.plain(built.text)
            for range in built.italics { b.addItalic(NSRange(location: offset + range.location, length: range.length)) }
            b.end()
        }
        if let link = fields.doiLink ?? fields.url { b.part(link); b.end() }
        return b.finish()
    }
}

extension ReferenceBuilder {
    /// Adds an italic range for text that was already appended.
    mutating func addItalic(_ range: NSRange) { italics.append(range) }
}

// MARK: Chicago author-date 17

enum Chicago {
    private static func inverted(_ name: BibliographyName) -> String {
        var result = name.surname
        if !name.first.isEmpty { result += ", " + name.first }
        if !name.jr.isEmpty { result += ", " + name.jr }
        return result
    }

    private static func direct(_ name: BibliographyName) -> String {
        [name.first, name.surname].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Up to ten authors are listed; longer lists show the first seven and "et al.".
    static func names(_ people: [BibliographyName]) -> String {
        let hasOthers = people.contains { $0.isOthers }
        var named = people.filter { !$0.isOthers }
        guard !named.isEmpty else { return "" }
        var truncated = hasOthers
        if named.count > 10 { named = Array(named.prefix(7)); truncated = true }
        var parts = [inverted(named[0])] + named.dropFirst().map(direct)
        if truncated { return parts.joined(separator: ", ") + ", et al." }
        if parts.count == 1 { return parts[0] }
        let last = parts.removeLast()
        return parts.joined(separator: ", ") + ", and " + last
    }

    static func format(_ fields: ReferenceFields) -> FormattedReference {
        var b = ReferenceBuilder()
        let authors = fields.authors
        let creators = authors.isEmpty ? fields.editors : authors
        if !creators.isEmpty {
            b.plain(names(creators) + (authors.isEmpty ? (creators.count > 1 ? ", eds" : ", ed") : ""))
            b.end()
        }
        b.part((fields.year ?? "n.d.") + ".")
        let quoted = fields.kind == .article || fields.kind == .proceedings || fields.kind == .chapter
        if let title = fields.title {
            if quoted { b.part("“" + title + (title.last.map { ".?!".contains($0) } == true ? "" : ".") + "”") }
            else { b.part(title, italic: true); b.end() }
        }
        switch fields.kind {
        case .article:
            if let journal = fields.journal {
                b.space(); b.italic(journal)
                if let volume = fields.volume { b.plain(" " + volume) }
                if let number = fields.number { b.plain(" (" + number + ")") }
                if let pages = fields.pages(separator: "–") { b.plain(": " + pages) }
                b.end()
            }
        case .proceedings, .chapter:
            if let book = fields.bookTitle {
                b.space(); b.plain("In "); b.italic(book)
                if let pages = fields.pages(separator: "–") { b.plain(", " + pages) }
                b.end()
            }
            b.place(fields)
        default:
            if let edition = fields.edition { b.part(ordinal(edition) + " ed."); }
            b.place(fields)
        }
        if let link = fields.doiLink ?? fields.url { b.part(link); b.end() }
        return b.finish()
    }
}

extension ReferenceBuilder {
    /// "Place: Publisher." in the Chicago manner, with whichever parts exist.
    mutating func place(_ fields: ReferenceFields) {
        let publisher = fields.publisher ?? fields.institution ?? fields.howPublished
        switch (fields.address, publisher) {
        case let (address?, publisher?): part(address + ": " + publisher); end()
        case let (nil, publisher?): part(publisher); end()
        case let (address?, nil): part(address); end()
        default: break
        }
    }
}

// MARK: IEEE

enum IEEE {
    private static func formatted(_ name: BibliographyName) -> String {
        var result = [name.initials, name.surname].filter { !$0.isEmpty }.joined(separator: " ")
        if !name.jr.isEmpty { result += ", " + name.jr }
        return result
    }

    /// Up to six authors; more are shortened to the first author and "et al.".
    static func names(_ people: [BibliographyName]) -> String {
        let hasOthers = people.contains { $0.isOthers }
        let named = people.filter { !$0.isOthers }.map(formatted)
        guard !named.isEmpty else { return "" }
        if named.count > 6 || hasOthers { return named[0] + " et al." }
        switch named.count {
        case 1: return named[0]
        case 2: return named[0] + " and " + named[1]
        default: return named.dropLast().joined(separator: ", ") + ", and " + named[named.count - 1]
        }
    }

    private static let monthNames = ["Jan.", "Feb.", "Mar.", "Apr.", "May", "Jun.", "Jul.", "Aug.", "Sep.", "Oct.", "Nov.", "Dec."]

    static func format(_ fields: ReferenceFields) -> FormattedReference {
        var b = ReferenceBuilder()
        let authors = fields.authors
        let creators = authors.isEmpty ? fields.editors : authors
        var lead: [String] = []
        if !creators.isEmpty { lead.append(names(creators) + (authors.isEmpty ? (creators.count > 1 ? ", Eds." : ", Ed.") : "")) }
        let date = [fields.monthNumber.map { monthNames[$0 - 1] }, fields.year].compactMap { $0 }.joined(separator: " ")
        switch fields.kind {
        case .article:
            if !lead.isEmpty { b.plain(lead[0] + ", ") }
            if let title = fields.title { b.plain("“" + title + ",”") }
            if let journal = fields.journal { b.space(); b.italic(journal) }
            for piece in [fields.volume.map { "vol. " + $0 }, fields.number.map { "no. " + $0 },
                          fields.pages(separator: "–").map { "pp. " + $0 }, date.isEmpty ? nil : date] {
                guard let piece else { continue }
                b.plain(b.isEmpty ? "" : b.text.hasSuffix(",”") ? " " : ", ")
                b.plain(piece)
            }
            if let doi = fields.doi { b.plain(", doi: " + doi) }
            b.end()
        case .proceedings, .chapter:
            if !lead.isEmpty { b.plain(lead[0] + ", ") }
            if let title = fields.title { b.plain("“" + title + ",”") }
            if let book = fields.bookTitle { b.space(); b.plain("in "); b.italic(book) }
            for piece in [fields.address, date.isEmpty ? nil : date, fields.pages(separator: "–").map { "pp. " + $0 }] {
                guard let piece else { continue }
                b.plain(", " + piece)
            }
            if let doi = fields.doi { b.plain(", doi: " + doi) }
            b.end()
        default:
            if !lead.isEmpty { b.plain(lead[0] + ", ") }
            if let title = fields.title {
                if fields.kind == .book { b.italic(title) } else { b.plain("“" + title + ",”") }
            }
            if let edition = fields.edition { b.plain(", " + ordinal(edition) + " ed") }
            var imprint = ""
            if let address = fields.address { imprint += address }
            if let publisher = fields.publisher ?? fields.institution ?? fields.howPublished {
                imprint += (imprint.isEmpty ? "" : ": ") + publisher
            }
            if !date.isEmpty { imprint += (imprint.isEmpty ? "" : ", ") + date }
            if !imprint.isEmpty { b.plain(b.isEmpty ? imprint : ". " + imprint) }
            if let doi = fields.doi { b.plain(", doi: " + doi) } else if let url = fields.url { b.plain(", " + url) }
            b.end()
        }
        return b.finish()
    }
}
