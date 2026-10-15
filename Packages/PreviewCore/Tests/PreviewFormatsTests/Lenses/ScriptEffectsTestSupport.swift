import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// One finding reduced to what the tests compare: its kind, its count and its lines.
struct ScriptFact: Equatable, Sendable, CustomStringConvertible {
    let kind: PreviewFindingKind
    let count: Int
    let lines: [Int]

    init(_ kind: PreviewFindingKind, _ count: Int, _ lines: [Int]) {
        self.kind = kind
        self.count = count
        self.lines = lines
    }

    var description: String { "\(kind.rawValue) x\(count) @\(lines)" }
}

/// A script and the facts the lens must report for it, in the contract's kind order. An empty list means
/// the lens must stay silent.
struct ScriptCase: Sendable, CustomTestStringConvertible {
    let name: String
    let language: SourceLanguageID
    let script: String
    let expected: [ScriptFact]

    init(_ name: String, _ script: String, language: SourceLanguageID = .shell, _ expected: [ScriptFact] = []) {
        self.name = name
        self.language = language
        self.script = script
        self.expected = expected
    }

    var testDescription: String { name }

    func check(sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(try ScriptFixture.facts(script, language: language) == expected, "\(name)", sourceLocation: sourceLocation)
    }
}

enum ScriptFixture {
    static func findings(_ text: String, language: SourceLanguageID? = .shell, format: FormatID = .sourceCode,
                         fileName: String = "script", context: RequestContext = RequestContext(budget: .standard)) throws -> [PreviewFinding] {
        let request = PreviewLensRequest(formatID: format, fileName: fileName, sourceLanguage: language)
        return try ScriptEffectsLens().findings(in: text, request: request, context: context)
    }

    /// The facts of a script's findings in the contract's kind order, whatever order the lens produced them in.
    static func facts(_ text: String, language: SourceLanguageID? = .shell, format: FormatID = .sourceCode,
                      fileName: String = "script") throws -> [ScriptFact] {
        try findings(text, language: language, format: format, fileName: fileName)
            .sorted { $0.kind.declarationOrder < $1.kind.declarationOrder }
            .map { ScriptFact($0.kind, $0.count, $0.lines) }
    }
}

extension PreviewFindingKind {
    /// Declaration order, which the contract uses as its tie-breaker.
    var declarationOrder: Int { Self.allCases.firstIndex(of: self) ?? Int.max }
}

/// Shorthand for the nine kinds: a count (default 1) and the lines (default line 1).
extension ScriptFact {
    static func downloadAndRun(_ count: Int = 1, at lines: [Int] = [1]) -> ScriptFact { ScriptFact(.scriptDownloadAndRun, count, lines) }
    static func decodeAndRun(_ count: Int = 1, at lines: [Int] = [1]) -> ScriptFact { ScriptFact(.scriptDecodeAndRun, count, lines) }
    static func quarantine(_ count: Int = 1, at lines: [Int] = [1]) -> ScriptFact { ScriptFact(.scriptRemovesQuarantine, count, lines) }
    static func protection(_ count: Int = 1, at lines: [Int] = [1]) -> ScriptFact { ScriptFact(.scriptDisablesProtection, count, lines) }
    static func password(_ count: Int = 1, at lines: [Int] = [1]) -> ScriptFact { ScriptFact(.scriptAsksForPassword, count, lines) }
    static func secrets(_ count: Int = 1, at lines: [Int] = [1]) -> ScriptFact { ScriptFact(.scriptReadsSecrets, count, lines) }
    static func persistence(_ count: Int = 1, at lines: [Int] = [1]) -> ScriptFact { ScriptFact(.scriptPersistence, count, lines) }
    static func elevates(_ count: Int = 1, at lines: [Int] = [1]) -> ScriptFact { ScriptFact(.scriptElevates, count, lines) }
    static func uploads(_ count: Int = 1, at lines: [Int] = [1]) -> ScriptFact { ScriptFact(.scriptUploadsFiles, count, lines) }
}
