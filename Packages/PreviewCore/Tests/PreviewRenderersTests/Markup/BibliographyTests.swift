import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private func entry(_ fields: [String: String], key: String = "k") -> BibliographyEntry {
    BibliographyEntry(type: "article", key: key, fields: fields)
}

private func entry(_ type: String, _ fields: [String: String]) -> BibliographyEntry {
    BibliographyEntry(type: type, key: "k", fields: fields)
}

private func formatted(_ entry: BibliographyEntry, _ style: BibliographyStyle) -> String {
    BibliographyFormatter.format(entry, style: style).text
}

@Suite("BibTeX parsing")
struct BibTeXParsingTests {
    @Test func bracedQuotedNumericAndMacroValuesConcatenate() throws {
        let source = """
        @string{ jacm = "Journal of the ACM" }
        @string{first = {Ada}}
        @article{k1,
          author = first # { Lovelace} # " and " # {Babbage, C.},
          title = {A {Nested {Brace}} Title},
          journal = jacm,
          year = 1843,
          month = mar,
          note = "quote with {braces \\" inside} here"
        }
        """
        let bibliography = try #require(SafeBibliography.parse(source))
        let item = try #require(bibliography.entries.first)
        #expect(item.type == "article")
        #expect(item.key == "k1")
        #expect(item.fields["author"] == "Ada Lovelace and Babbage, C.")
        #expect(item.fields["title"] == "A {Nested {Brace}} Title")
        #expect(item.fields["journal"] == "Journal of the ACM")
        #expect(item.fields["year"] == "1843")
        #expect(item.fields["month"] == "March")
        #expect(item.field("title") == "A Nested Brace Title")
    }

    @Test func commentsPreamblesAndTextBetweenEntriesAreIgnored() throws {
        let source = """
        This is free text with @ signs and password: ••••
        @comment{ @article{ignored, title = {x}} }
        @preamble{ "\\newcommand{\\noop}[1]{}" }
        @book(bk, title = {Paren Entry}, year = {2000})
        @misc{m1, title = {Second}}
        """
        let bibliography = try #require(SafeBibliography.parse(source))
        #expect(bibliography.entries.map(\.key) == ["bk", "m1"])
        #expect(bibliography.entries[0].field("title") == "Paren Entry")
    }

    @Test func typesAndFieldNamesAreCaseInsensitiveAndFirstDuplicateWins() throws {
        let bibliography = try #require(SafeBibliography.parse("@ARTICLE{k, TITLE = {One}, Title = {Two}}"))
        #expect(bibliography.entries[0].type == "article")
        #expect(bibliography.entries[0].field("title") == "One")
    }

    @Test func malformedFieldsAndMissingClosingBracesRecoverAtTheNextEntry() throws {
        let source = """
        @article{noclose, title = {Kept},
        @book{ok, title = {Fine}}
        @article{noequals, justaword, title = {Also kept}}
        @article{ , title = {No key}}
        @misc{weird = , title = {W}}
        """
        let bibliography = try #require(SafeBibliography.parse(source))
        #expect(bibliography.entries.first { $0.key == "noclose" }?.field("title") == "Kept")
        #expect(bibliography.entries.first { $0.key == "ok" }?.field("title") == "Fine")
        #expect(bibliography.entries.first { $0.key == "noequals" }?.field("title") == "Also kept")
        #expect(bibliography.entries.count >= 4)
    }

    @Test func anUnclosedBraceKeepsItsTextAndEndsTheFileAsBibTeXDoes() throws {
        let bibliography = try #require(SafeBibliography.parse("@article{open1,\n  title = {never closed\n@book{ok, title = {Fine}}"))
        #expect(bibliography.entries.count == 1)
        #expect(bibliography.entries[0].field("title")?.hasPrefix("never closed") == true)
    }

    @Test func emptyOrEntryFreeTextHasNoBibliography() {
        #expect(SafeBibliography.parse("") == nil)
        #expect(SafeBibliography.parse("just notes, no entries @ here") == nil)
        #expect(SafeBibliography.parse("@comment{only a comment}") == nil)
    }

    @Test func entryFieldAndValueBoundsHold() throws {
        let many = (0..<5_200).map { "@misc{k\($0), title = {t}}" }.joined(separator: "\n")
        #expect(try #require(SafeBibliography.parse(many)).entries.count == SafeBibliography.maximumEntries)
        let fields = (0..<100).map { "f\($0) = {v}" }.joined(separator: ", ")
        #expect(try #require(SafeBibliography.parse("@misc{k, \(fields)}")).entries[0].fields.count == SafeBibliography.maximumFieldsPerEntry)
        let long = String(repeating: "x", count: 20_000)
        let value = try #require(SafeBibliography.parse("@misc{k, title = {\(long)}}")).entries[0].fields["title"]
        #expect((value?.utf16.count ?? 0) <= SafeBibliography.maximumValueUnits)
        #expect(SafeBibliography.parse(String(repeating: "@", count: SafeBibliography.maximumSourceUnits + 1)) == nil)
    }

    @Test func pathologicalInputTerminatesQuickly() {
        let started = ContinuousClock.now
        _ = SafeBibliography.parse(String(repeating: "@a{", count: 50_000))
        _ = SafeBibliography.parse(String(repeating: "{", count: 200_000))
        _ = SafeBibliography.parse("@a{k," + String(repeating: "x=", count: 100_000))
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test func concealedValuesPassThroughAsOpaqueText() throws {
        let bibliography = try #require(SafeBibliography.parse("@misc{k, title = {Safe}, password = ••••,\n year = 2020}"))
        #expect(bibliography.entries[0].fields["password"] == "••••")
        #expect(bibliography.entries[0].fields["year"] == "2020")
    }
}

@Suite("BibTeX names")
struct BibTeXNameTests {
    private func names(_ raw: String) -> [BibliographyName] { BibliographyNames.parse(raw) }

    @Test func allThreeBibTeXFormsSplitIntoFirstVonLastAndJunior() {
        let simple = names("Ada Byron Lovelace")[0]
        #expect((simple.first, simple.von, simple.last) == ("Ada Byron", "", "Lovelace"))
        let comma = names("Lovelace, Ada Byron")[0]
        #expect((comma.first, comma.von, comma.last) == ("Ada Byron", "", "Lovelace"))
        let von = names("Ludwig van Beethoven")[0]
        #expect((von.first, von.von, von.last) == ("Ludwig", "van", "Beethoven"))
        let vonComma = names("van der Berg, Jan")[0]
        #expect((vonComma.first, vonComma.von, vonComma.last) == ("Jan", "van der", "Berg"))
        let junior = names("Smith, Jr., John")[0]
        #expect((junior.first, junior.last, junior.jr) == ("John", "Smith", "Jr."))
        let lone = names("Plato")[0]
        #expect((lone.first, lone.last) == ("", "Plato"))
    }

    @Test func listsSplitOnAndOutsideBracesAndOthersIsAMarker() {
        let list = names("Lovelace, Ada and {Barnes and Noble} and\n  Charles Babbage and others")
        #expect(list.count == 4)
        #expect(list[1].last == "Barnes and Noble")
        #expect(list[1].first.isEmpty)
        #expect(list[2].last == "Babbage")
        #expect(list[3].isOthers)
    }

    @Test func accentsAndInitials() {
        let person = names(#"M\"uller, Jean-Paul Émile"#)[0]
        #expect(person.last == "Müller")
        #expect(person.initials == "J.-P. É.")
        #expect(names("Donald E. Knuth")[0].initials == "D. E.")
        #expect(names("Grace Murray Hopper")[0].initials == "G. M.")
    }

    @Test func nameListsAreBounded() {
        let many = (0..<500).map { "Person\($0), A." }.joined(separator: " and ")
        #expect(names(many).count == BibliographyNames.maximumNames)
    }
}

@Suite("Reference styles")
struct ReferenceStyleTests {
    private let lovelaceBabbage = "Lovelace, Ada and Babbage, Charles"

    private var article: BibliographyEntry {
        entry(["author": lovelaceBabbage, "title": "Notes on the Analytical Engine", "journal": "Scientific Memoirs",
               "year": "1843", "volume": "3", "number": "2", "pages": "666--731", "doi": "10.1000/xyz"], key: "a")
    }

    @Test func apaArticleBookAndProceedings() {
        #expect(formatted(article, .apa) == "Lovelace, A., & Babbage, C. (1843). Notes on the Analytical Engine. Scientific Memoirs, 3(2), 666–731. https://doi.org/10.1000/xyz")
        let book = entry("book", ["author": "Knuth, Donald E.", "title": "The {TeXbook}", "publisher": "Addison-Wesley", "address": "Reading, MA", "year": "1984", "edition": "2"])
        #expect(formatted(book, .apa) == "Knuth, D. E. (1984). The TeXbook (2nd ed.). Addison-Wesley.")
        let proceedings = entry("inproceedings", ["author": "Hopper, Grace Murray", "title": "The Education of a Computer", "booktitle": "Proceedings of the 1952 ACM National Meeting", "year": "1952", "pages": "243--249"])
        #expect(formatted(proceedings, .apa) == "Hopper, G. M. (1952). The Education of a Computer. In Proceedings of the 1952 ACM National Meeting (pp. 243–249).")
    }

    @Test func apaItalicsCoverJournalVolumeAndBookTitles() {
        let reference = BibliographyFormatter.format(article, style: .apa)
        let italic = reference.italics.map { (reference.text as NSString).substring(with: $0) }
        #expect(italic == ["Scientific Memoirs", "3"])
        let book = BibliographyFormatter.format(entry("book", ["author": "A, B", "title": "Title", "year": "2000"]), style: .apa)
        #expect(book.italics.map { (book.text as NSString).substring(with: $0) } == ["Title"])
    }

    @Test func apaAuthorLists() {
        func authors(_ count: Int) -> String {
            let list = (1...count).map { "Surname\($0), First\($0)" }.joined(separator: " and ")
            return formatted(entry(["author": list, "title": "T", "year": "2000"]), .apa)
        }
        #expect(authors(1).hasPrefix("Surname1, F. (2000)."))
        #expect(authors(2).hasPrefix("Surname1, F., & Surname2, F. (2000)."))
        #expect(authors(3).hasPrefix("Surname1, F., Surname2, F., & Surname3, F. (2000)."))
        let twentyOne = authors(21)
        #expect(twentyOne.contains("Surname19, F., . . . Surname21, F."))
        #expect(!twentyOne.contains("Surname20"))
        #expect(formatted(entry(["author": "Lovelace, Ada and others", "title": "T", "year": "2000"]), .apa).hasPrefix("Lovelace, A., et al. (2000)."))
    }

    @Test func apaMissingFieldsDegradeGracefully() {
        #expect(formatted(entry(["title": "Only a title"]), .apa) == "Only a title. (n.d.).")
        #expect(formatted(entry("book", ["title": "Book title", "year": "1999"]), .apa) == "Book title. (1999).")
        #expect(formatted(entry(["author": "Doe, Jane", "journal": "J"]), .apa) == "Doe, J. (n.d.). J.")
        #expect(formatted(entry("misc", [:]), .apa) == "(n.d.).")
        #expect(formatted(entry(["editor": "Doe, Jane", "title": "T", "year": "2001"]), .apa).hasPrefix("Doe, J. (Ed.). (2001)."))
        #expect(formatted(entry("phdthesis", ["author": "Doe, Jane", "title": "Deep thoughts", "school": "State University", "year": "2005"]), .apa)
                == "Doe, J. (2005). Deep thoughts [Doctoral dissertation, State University].")
    }

    @Test func mlaFormatsFullNamesAndEtAl() {
        #expect(formatted(article, .mla) == "Lovelace, Ada, and Charles Babbage. “Notes on the Analytical Engine.” Scientific Memoirs, vol. 3, no. 2, 1843, pp. 666-731. https://doi.org/10.1000/xyz.")
        let book = entry("book", ["author": "Knuth, Donald E.", "title": "The {TeXbook}", "publisher": "Addison-Wesley", "year": "1984"])
        #expect(formatted(book, .mla) == "Knuth, Donald E. The TeXbook. Addison-Wesley, 1984.")
        let three = entry(["author": "A, Ann and B, Bob and C, Cy", "title": "T", "journal": "J", "year": "2000"])
        #expect(formatted(three, .mla) == "A, Ann, et al. “T.” J, 2000.")
        #expect(formatted(entry(["title": "Anonymous piece", "journal": "J", "year": "2000"]), .mla) == "“Anonymous piece.” J, 2000.")
    }

    @Test func chicagoAuthorDateOrdersYearAfterTheAuthors() {
        #expect(formatted(article, .chicago) == "Lovelace, Ada, and Charles Babbage. 1843. “Notes on the Analytical Engine.” Scientific Memoirs 3 (2): 666–731. https://doi.org/10.1000/xyz.")
        let book = entry("book", ["author": "Knuth, Donald E.", "title": "The {TeXbook}", "publisher": "Addison-Wesley", "address": "Reading, MA", "year": "1984"])
        #expect(formatted(book, .chicago) == "Knuth, Donald E. 1984. The TeXbook. Reading, MA: Addison-Wesley.")
        let three = entry(["author": "A, Ann and B, Bob and C, Cy", "title": "T", "journal": "J", "year": "2000"])
        #expect(formatted(three, .chicago).hasPrefix("A, Ann, Bob B, and Cy C. 2000."))
        let eleven = (1...11).map { "Last\($0), First\($0)" }.joined(separator: " and ")
        let long = formatted(entry(["author": eleven, "title": "T", "year": "2000"]), .chicago)
        #expect(long.contains("First7 Last7, et al."))
        #expect(!long.contains("Last8"))
        #expect(formatted(entry(["title": "No author", "year": "2000"]), .chicago) == "2000. “No author.”")
        #expect(formatted(entry(["author": "Doe, Jane", "title": "T"]), .chicago).hasPrefix("Doe, Jane. n.d."))
    }

    @Test func ieeeUsesInitialsFirstAndEtAlBeyondSixAuthors() {
        #expect(formatted(article, .ieee) == "A. Lovelace and C. Babbage, “Notes on the Analytical Engine,” Scientific Memoirs, vol. 3, no. 2, pp. 666–731, 1843, doi: 10.1000/xyz.")
        let book = entry("book", ["author": "Knuth, Donald E.", "title": "The {TeXbook}", "publisher": "Addison-Wesley", "address": "Reading, MA", "year": "1984"])
        #expect(formatted(book, .ieee) == "D. E. Knuth, The TeXbook. Reading, MA: Addison-Wesley, 1984.")
        let seven = (1...7).map { "Last\($0), First\($0)" }.joined(separator: " and ")
        #expect(formatted(entry(["author": seven, "title": "T", "journal": "J", "year": "2000"]), .ieee).hasPrefix("F. Last1 et al., “T,”"))
        let six = (1...6).map { "Last\($0), First\($0)" }.joined(separator: " and ")
        #expect(formatted(entry(["author": six, "title": "T", "year": "2000"]), .ieee).contains("F. Last5, and F. Last6"))
        let dated = entry(["author": "Doe, Jane", "title": "T", "journal": "J", "year": "2020", "month": "mar"])
        #expect(formatted(dated, .ieee) == "J. Doe, “T,” J, Mar. 2020.")
        #expect(formatted(entry(["title": "Only"]), .ieee) == "“Only.”")
    }

    @Test func conferenceAndChapterEntriesUseTheirContainers() {
        let paper = entry("inproceedings", ["author": "Hopper, Grace Murray", "title": "The Education of a Computer", "booktitle": "Proc. ACM", "year": "1952", "pages": "243--249", "address": "Pittsburgh"])
        #expect(formatted(paper, .mla) == "Hopper, Grace Murray. “The Education of a Computer.” Proc. ACM, 1952, pp. 243-249.")
        // Without a publisher, the place alone follows the pages.
        #expect(formatted(paper, .chicago) == "Hopper, Grace Murray. 1952. “The Education of a Computer.” In Proc. ACM, 243–249. Pittsburgh.")
        #expect(formatted(paper, .ieee) == "G. M. Hopper, “The Education of a Computer,” in Proc. ACM, Pittsburgh, 1952, pp. 243–249.")
        let chapter = entry("incollection", ["author": "Doe, Jane", "editor": "Roe, Richard", "title": "Chapter", "booktitle": "The Book", "year": "2010", "publisher": "Press"])
        #expect(formatted(chapter, .apa) == "Doe, J. (2010). Chapter. In R. Roe (Ed.), The Book. Press.")
        #expect(formatted(chapter, .mla).contains("edited by Richard Roe"))
    }

    @Test func texAccentsAndBracesAreCleanedInEveryStyle() {
        let item = entry(["author": #"M\"uller, J{\"o}rg"#, "title": "The {DNA} of {TeX}", "journal": "J", "year": "2020"])
        for style in BibliographyStyle.allCases {
            let text = formatted(item, style)
            #expect(text.contains("Müller") || text.contains("Jörg"))
            #expect(text.contains("The DNA of TeX"))
            #expect(!text.contains("{") && !text.contains("\\"))
        }
    }

    @Test func urlsAreShownAsPlainTextAndNeverBecomeLinks() {
        let item = entry("misc", ["author": "Doe, Jane", "title": "Page", "year": "2020", "url": "https://example.invalid/page"])
        for style in BibliographyStyle.allCases {
            #expect(formatted(item, style).contains("https://example.invalid/page"))
        }
        let document = BibliographyFormatter.document(SafeBibliography(entries: [item]), style: .apa)
        #expect(document?.decorations.contains { if case .heading = $0.style { true } else { false } } == false)
    }

    @Test func concealedFieldValuesStayConcealedInEveryStyle() {
        let item = entry(["author": "Doe, Jane", "title": "Notes", "journal": "J", "year": "2020", "note": "••••", "doi": "••••"])
        for style in BibliographyStyle.allCases {
            let text = formatted(item, style)
            #expect(!text.contains("synthetic"))
        }
        #expect(formatted(item, .apa).contains("https://doi.org/••••"))
    }
}

@Suite("Reference list document")
struct ReferenceDocumentTests {
    private let source = """
    @book{zeta, author = {Zeta, Zed}, title = {Last by name}, year = {2001}, publisher = {P}}
    @article{alpha2, author = {Alpha, Ann}, title = {Second by year}, journal = {J}, year = {2020}}
    @article{alpha1, author = {Alpha, Ann}, title = {First by year}, journal = {J}, year = {2010}}
    @misc{nobody, title = {Beta Title}, year = {2005}}
    """

    @Test func authorStylesSortByAuthorThenYearAndIEEEKeepsFileOrder() throws {
        let bibliography = try #require(SafeBibliography.parse(source))
        let apa = try #require(BibliographyFormatter.document(bibliography, style: .apa))
        #expect(apa.headings.map(\.title) == ["alpha1", "alpha2", "nobody", "zeta"])
        let ieee = try #require(BibliographyFormatter.document(bibliography, style: .ieee))
        #expect(ieee.headings.map(\.title) == ["zeta", "alpha2", "alpha1", "nobody"])
        #expect(ieee.lines.filter { !$0.isEmpty }.map { String($0.prefix(3)) } == ["[1]", "[2]", "[3]", "[4]"])
    }

    @Test func everyEntryIsOneHangingParagraphWithItsKeyAsAHeading() throws {
        let bibliography = try #require(SafeBibliography.parse(source))
        let document = try #require(BibliographyFormatter.document(bibliography, style: .apa))
        #expect(document.lines.filter { !$0.isEmpty }.count == 4)
        #expect(document.decorations.filter { if case .listItem = $0.style { true } else { false } }.count == 4)
        for heading in document.headings { #expect(document.substring(heading.range).isEmpty == false) }
    }

    @Test func italicDecorationsFollowTheFormattedText() throws {
        let bibliography = try #require(SafeBibliography.parse(source))
        let document = try #require(BibliographyFormatter.document(bibliography, style: .apa))
        #expect(Set(document.ranges(of: .italic)).isSuperset(of: ["J", "Last by name", "Beta Title"]))
        #expect(document.decorations.allSatisfy { NSMaxRange($0.range) <= document.text.utf16.count })
    }

    @Test func rightToLeftTitlesAreTagged() throws {
        let bibliography = try #require(SafeBibliography.parse("@misc{ar, title = {عنوان عربي}, year = {2020}}\n@misc{en, author = {Zed, Z}, title = {English}, year = {2020}}"))
        let document = try #require(BibliographyFormatter.document(bibliography, style: .apa))
        // The Arabic entry has no author, so its title leads and sets the paragraph direction.
        #expect(document.ranges(of: .rightToLeft).contains { $0.contains("عنوان عربي") })
    }

    @Test func largeBibliographiesFormatInBoundedTime() throws {
        let entries = (0..<2_000).map { "@article{k\($0), author = {Author\($0), First}, title = {Title \($0)}, journal = {Journal}, year = {\(1900 + $0 % 120)}, pages = {1--9}}" }
        let bibliography = try #require(SafeBibliography.parse(entries.joined(separator: "\n")))
        let started = ContinuousClock.now
        for style in BibliographyStyle.allCases { _ = BibliographyFormatter.document(bibliography, style: style) }
        #expect(ContinuousClock.now - started < .seconds(15))
    }
}
