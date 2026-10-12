import Foundation
import Synchronization
import Testing
import UniformTypeIdentifiers
import PreviewContracts
@testable import PreviewCore
import PreviewFormats

private let secret = "synthetic-secret-value"

private final class ReadCounter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

private struct FixedReader: PreviewFileReading {
    let data: Data
    let reads: ReadCounter
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        reads.increment()
        return FileBytes(data: data)
    }
}

private struct UndeclaredMarkupType: PreviewContentTypeReading {
    func contentType(for url: URL) throws -> UTType? { nil }
}

private let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)

private func preview(_ text: String, file: String, budget: PreviewBudget? = nil) async -> PreviewOutcome {
    let custom = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                 reader: FixedReader(data: Data(text.utf8), reads: ReadCounter()))
    return await custom.preview(url: URL(fileURLWithPath: "/unused/" + file), budget: budget)
}

private func ready(_ text: String, file: String) async -> TextPresentation? {
    if case .ready(let presentation) = await preview(text, file: file) { return presentation }
    return nil
}

@Suite("Markup formats through the shared pipeline")
struct MarkupPipelineTests {
    private static let samples: [(id: FormatID, file: String, syntax: TextSyntax, text: String)] = [
        (.markdown, "notes.md", .markdown, "# Notes\n\npassword: \(secret)\n"),
        (.latex, "paper.tex", .latex, "\\def\\apikey{\(secret)}\n% token: \(secret)\n\\begin{document}\n\\section{Safe}\n\\end{document}\n"),
        (.bibtex, "refs.bib", .bibtex, "@article{k, title = {Safe}, password = {\(secret)}, year = {2020}}\n"),
        (.asciidoc, "doc.adoc", .asciidoc, "= Title\n:api-key: \(secret)\n// token = \(secret)\n\n== Safe\n"),
        (.restructuredText, "doc.rst", .restructuredText, "Title\n=====\n\n:password: \(secret)\n\n.. |token| replace:: \(secret)\n"),
        (.org, "notes.org", .orgMode, "#+TITLE: T\n#+PROPERTY: password \(secret)\n\n* Safe\n:PROPERTIES:\n:TOKEN: \(secret)\n:END:\n"),
        (.fountain, "script.fountain", .fountain, "Title: Safe\nPassword: \(secret)\n\nINT. ROOM - DAY\n\nText\n")
    ]

    @Test(arguments: samples)
    func everyFormatIsReadyConcealsSyntaxSpecificSecretsAndKeepsSafeText(sample: (id: FormatID, file: String, syntax: TextSyntax, text: String)) async throws {
        let result = try #require(await ready(sample.text, file: sample.file))
        #expect(result.formatID == sample.id)
        #expect(result.syntax == sample.syntax)
        #expect(result.encoding == .utf8)
        #expect(!result.text.contains(secret))
        #expect(result.redactionCount >= 1)
        #expect(result.text.contains("Safe") || result.text.contains("Notes") || result.text.contains("Title"))
    }

    @Test func markdownFrontMatterBlockScalarsAndQuotedKeysAreConcealedWithoutHidingTheBody() async throws {
        let yaml = "---\ntitle: Report\npassword: |\n  \(secret)-one\n  \(secret)-two\n\"api_key\": \(secret)-three\n---\n# Body stays\n\nText after.\n"
        let result = try #require(await ready(yaml, file: "report.md"))
        #expect(!result.text.contains("synthetic-secret"))
        #expect(result.text.contains("# Body stays"))
        #expect(result.text.contains("Text after."))
        #expect(result.text.contains("title: Report"))
        let toml = "+++\ntitle = \"Report\"\ntoken = \"\(secret)\"\napi_key = '\(secret)-two'\n+++\n# Body stays\n"
        let tomlResult = try #require(await ready(toml, file: "report.md"))
        #expect(!tomlResult.text.contains("synthetic-secret"))
        #expect(tomlResult.text.contains("# Body stays"))
        #expect(tomlResult.text.contains("title = \"Report\""))
        // A triple-quoted secret starts a value the shared policy cannot bound, so it hides the rest (fail closed).
        let multiline = "+++\npassword = '''\n\(secret)\n'''\n+++\n# Body\n"
        #expect(try #require(await ready(multiline, file: "report.md")).text.contains(secret) == false)
    }

    @Test func latexMacroNamesCommentsAndMultilineGroupsAreConcealed() async throws {
        let source = "\\newcommand{\\password}{\(secret)-a}\n\\password{\(secret)-b}\n\\def\\token{\n\(secret)-c\n}\n% api_key = \(secret)-d\n\\begin{document}\nVisible words.\n\\end{document}\n"
        let result = try #require(await ready(source, file: "paper.tex"))
        #expect(!result.text.contains("synthetic-secret"))
        #expect(result.text.contains("Visible words."))
        #expect(result.redactionCount >= 3)
    }

    @Test(arguments: [("a.sty", "\\def\\secret{\(secret)}\n"), ("a.cls", "% password: \(secret)\n"), ("a.ltx", "\\apikey{\(secret)}\n")])
    func everyLatexSuffixSharesTheSamePlanner(file: String, source: String) async throws {
        let result = try #require(await ready(source, file: file))
        #expect(result.formatID == .latex)
        #expect(!result.text.contains(secret))
    }

    @Test(arguments: ["a.mdx", "a.rmd", "a.qmd", "a.mkdn", "a.mdwn", "a.mdtxt", "a.mdtext", "a.markdn"])
    func extraMarkdownSuffixesUseTheMarkdownAdapterAndItsPrivacyRules(file: String) async throws {
        let result = try #require(await ready("---\ntoken: \(secret)\n---\n# Title\n", file: file))
        #expect(result.formatID == .markdown)
        #expect(result.syntax == .markdown)
        #expect(!result.text.contains(secret))
        #expect(result.text.contains("# Title"))
    }

    @Test func recognizableCredentialValuesInProseAreConcealedInEveryFormat() async throws {
        let token = "sk-synthetic-test-value-0001"
        for sample in Self.samples {
            let result = try #require(await ready("Deploy using \(token) now.\n", file: sample.file))
            #expect(!result.text.contains(token), "\(sample.id.rawValue)")
            #expect(result.text.contains("Deploy using"))
        }
    }

    @Test func armoredPGPFilesAreNotClaimedByAnyMarkupFormat() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("key.asc")
        let bytes = Data("-----BEGIN PGP PUBLIC KEY BLOCK-----".utf8)
        try bytes.write(to: url)
        let reads = ReadCounter()
        // Installed third-party UTTypes vary; this contract covers an undeclared .asc source,
        // not a missing path or a claim about the machine's Launch Services registration.
        let custom = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                     reader: FixedReader(data: bytes, reads: reads),
                                     classifier: PreviewFileClassifier(access: BoundedReadAccess(),
                                                                       contentTypes: UndeclaredMarkupType()))
        #expect(await custom.preview(url: url) == .unavailable(.unsupportedFormat))
        #expect(reads.value == 0)
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func disabledMarkupTypesAreNeverReadAndNeverConstructAnAdapter() async {
        for sample in Self.samples {
            let reads = ReadCounter()
            let constructed = ReadCounter()
            let registration = AdapterRegistration(formatID: sample.id) { constructed.increment(); return LaTeXSourceAdapter() }
            let custom = PreviewPipeline(registrations: [registration], reader: FixedReader(data: Data(sample.text.utf8), reads: reads))
            var preferences = PreviewPreferencesSnapshot.defaults
            preferences.setEnabled(false, for: sample.id)
            let outcome = await custom.preview(url: URL(fileURLWithPath: "/unused/" + sample.file), preferences: preferences)
            #expect(outcome == .disabledByUser(sample.id), "\(sample.id.rawValue)")
            #expect(reads.value == 0 && constructed.value == 0)
        }
    }

    @Test func markdownSuffixesFollowTheMarkdownToggleAndNeverFallBackToPlainText() async {
        let reads = ReadCounter()
        let custom = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                     reader: FixedReader(data: Data("# x".utf8), reads: reads))
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .markdown)
        for suffix in ["md", "mdx", "qmd", "rmd"] {
            #expect(await custom.preview(url: URL(fileURLWithPath: "/unused/a.\(suffix)"), preferences: preferences) == .disabledByUser(.markdown))
        }
        #expect(reads.value == 0)
        // Disabling the new formats leaves plain text and Markdown alone.
        preferences = .defaults
        preferences.setEnabled(false, for: .latex)
        #expect(await custom.preview(url: URL(fileURLWithPath: "/unused/a.md"), preferences: preferences) != .disabledByUser(.markdown))
    }

    @Test func sourcesAreNeverMutatedAndNoSiblingFilesAreRead() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A sibling the document points at; if anything opened it, its content could appear in the output.
        try Data("SIBLING-CONTENT-MUST-NEVER-APPEAR".utf8).write(to: directory.appendingPathComponent("chapter.tex"))
        try Data("SIBLING-CONTENT-MUST-NEVER-APPEAR".utf8).write(to: directory.appendingPathComponent("part.adoc"))
        let documents = [("main.tex", "\\input{chapter}\n\\include{chapter}\n"), ("main.adoc", "include::part.adoc[]\n"),
                         ("main.rst", ".. include:: part.adoc\n"), ("main.org", "#+INCLUDE: \"chapter.tex\"\n"), ("main.md", "[a](chapter.tex)\n")]
        for (name, text) in documents {
            let url = directory.appendingPathComponent(name)
            let original = Data(text.utf8)
            try original.write(to: url)
            let before = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            guard case .ready(let result) = await pipeline.preview(url: url) else { Issue.record("Expected \(name) to be ready"); continue }
            #expect(!result.text.contains("SIBLING-CONTENT"))
            #expect(try Data(contentsOf: url) == original)
            #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == before)
        }
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: directory.path)).count == 7)
    }

    @Test func sourceBudgetsAndEncodingsApplyToTheNewFormats() async throws {
        #expect(await preview(String(repeating: "a", count: 200), file: "a.tex", budget: .init(maxInputBytes: 100)) == .unavailable(.inputTooLarge))
        #expect(await preview("a\nb\nc\nd", file: "a.bib", budget: .init(maxTextLines: 2)) == .unavailable(.tooManyLines))
        #expect(await preview(String(repeating: "a", count: 200), file: "a.org", budget: .init(maxLineUTF8Bytes: 100)) == .unavailable(.lineTooLong))
        let utf16 = Data([0xFF, 0xFE]) + Data("= Title\n\n== Café\n".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        let custom = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: FixedReader(data: utf16, reads: ReadCounter()))
        guard case .ready(let result) = await custom.preview(url: URL(fileURLWithPath: "/unused/a.adoc")) else {
            Issue.record("Expected a UTF-16 AsciiDoc preview"); return
        }
        #expect(result.encoding == .utf16LittleEndian)
        #expect(result.text.contains("Café"))
        let binary = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: FixedReader(data: Data([0x41, 0x00, 0x00, 0x00, 0x01, 0x02]), reads: ReadCounter()))
        let outcome = await binary.preview(url: URL(fileURLWithPath: "/unused/a.rst"))
        if case .ready = outcome { Issue.record("Binary content must not preview as text") }
    }

    @Test func cancelledRequestsProduceNoContent() async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return await pipeline.preview(url: URL(fileURLWithPath: "/unused/a.tex"))
        }
        #expect(await task.value == .cancelled)
    }

    @Test func fixtureStyleDocumentsKeepTheirAdvertisedStructureAfterConcealment() async throws {
        let bib = try #require(await ready("@article{a, author = {Doe, Jane}, title = {Safe}, year = {2020}}\n@article{b, author = {Roe, Rick}, title = {Other}, year = {2021}, password = {\(secret)}}\n", file: "refs.bib"))
        #expect(bib.text.contains("author = {Doe, Jane}"))
        #expect(!bib.text.contains(secret))
        #expect(bib.text.contains("@article{b"))
    }
}
