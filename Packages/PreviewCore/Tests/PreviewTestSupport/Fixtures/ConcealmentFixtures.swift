import Foundation
import PreviewContracts

/// Synthetic source bytes shared by concealment surface tests. These values are never credentials.
/// Expected source spellings are independent of every production classifier and renderer.
public struct ConcealmentFixture: Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case plainText, sourceCode, json, jsonLines, csv, markdown
    }

    public let kind: Kind
    public let formatID: FormatID
    public let fileName: String
    public let bytes: Data
    public let sentinel: String
    /// Exact spellings that are present in the source bytes before parsing.
    public let sourceCanaries: [String]
    /// Source spellings plus their independently declared decoded values.
    public let forbiddenStrings: [String]

    public init(kind: Kind, formatID: FormatID, fileName: String, source: String, sentinel: String,
                sourceCanaries: [String], decodedCanaries: [String]) {
        self.kind = kind
        self.formatID = formatID
        self.fileName = fileName
        self.bytes = Data(source.utf8)
        self.sentinel = sentinel
        self.sourceCanaries = sourceCanaries
        self.forbiddenStrings = sourceCanaries + decodedCanaries
    }
}

public enum ConcealmentFixtures {
    public static let sentinel = "Q151Safe"
    // The first two compare equal as Swift Strings but have different source code units.
    public static let valueCanaries = [
        "q151-e\u{301}-private", "q151-é-private", "q151-private\u{200B}-tail", "q151-private😀-tail"
    ]
    public static let codeHostingCanary = "ghp_" + String(repeating: "A1", count: 18)
    public static let escapedCodeHostingCanary = "g\\u0068p_" + String(repeating: "A1", count: 18)

    public static let firstTranche: [ConcealmentFixture] = {
        // The unsafe Tags are an ordinary note, not a canary. Source keeps them; copy hygiene and
        // thumbnail formatting may remove them. Their decoded finding detail must remain inert.
        let tags = String(String.UnicodeScalarView("notice".unicodeScalars.compactMap {
            Unicode.Scalar(0xE0000 + $0.value)
        }))
        let note = sentinel + "\u{200B} " + tags
        let passwords = valueCanaries.map { "password = \($0)" }.joined(separator: "\n")
        let sourcePasswords = valueCanaries.map { "let password = \"\($0)\"" }.joined(separator: "\n")
        let objects = valueCanaries.map { "{\"password\":\"\($0)\"}" }.joined(separator: ",")
        let records = valueCanaries.map {
            "{\"\(sentinel)\":\"\(note)\",\"password\":\"\($0)\"}"
        }.joined(separator: "\n")
        let csvRows = valueCanaries.map { "\(sentinel),\($0),\(note)" }.joined(separator: "\n")
        let common = valueCanaries + [codeHostingCanary]
        func fixture(_ kind: ConcealmentFixture.Kind, _ format: FormatID, _ file: String, _ source: String,
                     escaped: Bool = false) -> ConcealmentFixture {
            .init(kind: kind, formatID: format, fileName: file, source: source, sentinel: sentinel,
                  sourceCanaries: common + (escaped ? [escapedCodeHostingCanary] : []),
                  decodedCanaries: escaped ? [codeHostingCanary] : [])
        }
        return [
            fixture(.plainText, .plainText, "canary-text.txt", "\(sentinel)\n\(passwords)\n\(codeHostingCanary)\nnote: \(note)\n"),
            fixture(.sourceCode, .sourceCode, "canary-source.swift", "let label = \"\(sentinel)\"\n\(sourcePasswords)\nlet value = \"\(codeHostingCanary)\"\n// \(note)\n"),
            fixture(.json, .json, "canary-json.json", "{\"\(sentinel)\":\"\(note)\",\"records\":[\(objects)],\"payload\":\"\(codeHostingCanary)\",\"escaped\":\"\(escapedCodeHostingCanary)\"}\n", escaped: true),
            fixture(.jsonLines, .jsonLines, "canary-records.jsonl", "\(records)\n{\"\(sentinel)\":\"\(sentinel)\",\"payload\":\"\(codeHostingCanary)\",\"escaped\":\"\(escapedCodeHostingCanary)\"}\n", escaped: true),
            fixture(.csv, .csv, "canary-table.csv", "\(sentinel),password,note\n\(csvRows)\n\(sentinel),\(codeHostingCanary),\(sentinel)\n"),
            fixture(.markdown, .markdown, "canary-document.md", """
            # \(sentinel)

            \(passwords)

            ## \(sentinel) second heading

            An ordinary note: \(note)

            ```mermaid
            flowchart LR
              A[\(sentinel)] --> B[\(codeHostingCanary)]
            ```
            """)
        ]
    }()
}
