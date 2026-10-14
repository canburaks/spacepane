import Foundation
import PreviewContracts

// The shared vocabulary of the script-effects lens (decision 029): the nine effects it reports, the
// dialects it reads, and the small command model every dialect's lexer produces and every rule reads.
// Nothing here holds source text beyond one request; findings carry only kinds, counts and lines.

/// What a script would do when run, in the order the contract lists the kinds.
enum ScriptEffect: Int, CaseIterable {
    case downloadAndRun, decodeAndRun, removesQuarantine, disablesProtection, asksForPassword
    case readsSecrets, persistence, elevates, uploadsFiles

    var findingKind: PreviewFindingKind {
        switch self {
        case .downloadAndRun: .scriptDownloadAndRun
        case .decodeAndRun: .scriptDecodeAndRun
        case .removesQuarantine: .scriptRemovesQuarantine
        case .disablesProtection: .scriptDisablesProtection
        case .asksForPassword: .scriptAsksForPassword
        case .readsSecrets: .scriptReadsSecrets
        case .persistence: .scriptPersistence
        case .elevates: .scriptElevates
        case .uploadsFiles: .scriptUploadsFiles
        }
    }
}

/// Occurrences per effect with the first lines they start on. Lines arrive in text order, so a repeat
/// of the previous line is the only duplicate worth checking; the finding sorts and bounds them again.
struct ScriptEffectsTally {
    private var counts = [Int](repeating: 0, count: ScriptEffect.allCases.count)
    private var lines = [[Int]](repeating: [], count: ScriptEffect.allCases.count)

    mutating func add(_ effect: ScriptEffect, count: Int = 1, line: Int) {
        guard count > 0 else { return }
        let slot = effect.rawValue
        counts[slot] += count
        guard lines[slot].count < PreviewFinding.maximumLines, lines[slot].last != line else { return }
        lines[slot].append(line)
    }

    func findings() -> [PreviewFinding] {
        ScriptEffect.allCases.compactMap { effect in
            let slot = effect.rawValue
            return counts[slot] > 0 ? PreviewFinding(kind: effect.findingKind, count: counts[slot], lines: lines[slot]) : nil
        }
    }
}

/// The scripting languages the lens reads. Each has its own lexer; the rules are shared.
enum ScriptDialect: Sendable {
    case shell, fish, powerShell, batch, appleScript

    /// `nil` for every file the lens does not read: other formats, other languages, plain text.
    init?(request: PreviewLensRequest, text: String) {
        guard request.formatID == .sourceCode || request.formatID == .extensionlessText else { return nil }
        if let language = request.sourceLanguage {
            guard let dialect = Self(language: language) else { return nil }
            self = dialect
            return
        }
        // Normally the extension-free adapter has named the language from a `#!` line already.
        guard request.formatID == .extensionlessText, let dialect = Self(interpreterLine: text.prefix(while: { $0 != "\n" && $0 != "\r" }))
        else { return nil }
        self = dialect
    }

    init?(language: SourceLanguageID) {
        switch language {
        case .shell: self = .shell
        case .fish: self = .fish
        case .powerShell: self = .powerShell
        case .batch: self = .batch
        case .appleScript: self = .appleScript
        default: return nil
        }
    }

    /// The language a `#!` line names. The shell family, fish and PowerShell come from the detector the
    /// extension-free adapter uses; AppleScript through `osascript` it does not map. A `-l` option selects
    /// another language (JavaScript for Automation), which this lens does not read.
    init?(interpreterLine line: Substring) {
        guard line.hasPrefix("#!") else { return nil }
        if let language = SourceLanguageDetector.language(forInterpreterLine: line) {
            guard let dialect = Self(language: language) else { return nil }
            self = dialect
            return
        }
        let words = line.dropFirst(2).split(whereSeparator: { $0 == " " || $0 == "\t" })
        var program = words.first?.split(separator: "/").last
        var rest = words.dropFirst()
        if program == "env" { program = rest.first(where: { !$0.hasPrefix("-") })?.split(separator: "/").last; rest = rest.dropFirst() }
        guard program == "osascript", !rest.contains("-l") else { return nil }
        self = .appleScript
    }
}

// MARK: - Command model

/// How a command connects to the one after it.
enum ScriptOperator {
    case pipe, and, or, sequence
}

enum ScriptRedirectKind {
    case output, append, input, hereDocument, hereString, other
}

struct ScriptRedirect {
    var kind: ScriptRedirectKind
    var target: ScriptWord
    /// Bytes of a here-document's body in the scanned buffer, and the line it starts on.
    var body: Range<Int>?
    var bodyLine = 0
}

/// One word with its quoting removed. A substitution inside the word leaves a placeholder byte in
/// `text` and its commands in `substitutions`, so the rules can tell what a word is made of.
struct ScriptWord {
    var text: String
    var substitutions: [ScriptSubstitution] = []
    /// The word is exactly one substitution: `"$(curl ...)"`, `` `curl ...` `` or `<(curl ...)`.
    var isWholeSubstitution = false
    /// A leading `NAME=value` assignment.
    var isAssignment = false
    /// The word contains a quoted part.
    var isQuoted = false

    /// Stands for a substitution inside `text`.
    static let placeholder: UInt8 = 0x01
}

struct ScriptSubstitution {
    var list: ScriptCommandList
    var isProcess: Bool
}

struct ScriptCommand {
    var words: [ScriptWord] = []
    var redirects: [ScriptRedirect] = []
    var next: ScriptOperator = .sequence
}

/// Commands joined by operators up to an unquoted line break: the unit findings are reported for,
/// numbered by the line the first command starts on, whatever continuations follow.
struct ScriptCommandList {
    var commands: [ScriptCommand] = []
    var line: Int
}

/// Collects the bytes of one word while a lexer reads it: quoted and unquoted text, and the
/// substitutions inside it. Shared by every dialect's lexer.
struct ScriptWordBuilder {
    enum Assignment { case candidate, yes, no }
    /// A word keeps at most this many bytes.
    static let limit = 64 * 1024

    var text: [UInt8] = []
    var substitutions: [ScriptSubstitution] = []
    var literalCount = 0
    var assignment = Assignment.candidate
    var isQuoted = false

    mutating func append(_ byte: UInt8) {
        if text.count < Self.limit { text.append(byte) }
    }

    /// A byte of the word's own text. Only unquoted bytes before the first `=` decide whether the
    /// word is an assignment.
    mutating func literal(_ byte: UInt8, unquoted: Bool) {
        if assignment == .candidate {
            if !unquoted {
                assignment = .no
            } else if byte == 0x3D {
                assignment = literalCount > 0 ? .yes : .no
            } else {
                let isLetter = (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F
                let isDigit = byte >= 0x30 && byte <= 0x39
                if !(isLetter || (isDigit && literalCount > 0)) { assignment = .no }
            }
        }
        literalCount += 1
        append(byte)
    }

    /// A quote mark before the first `=` means the word is not an assignment.
    mutating func markQuoted() {
        isQuoted = true
        if assignment == .candidate { assignment = .no }
    }

    mutating func substitution(_ substitution: ScriptSubstitution?) {
        if let substitution { substitutions.append(substitution) }
        if assignment != .yes { assignment = .no }
        append(ScriptWord.placeholder)
    }

    func word() -> ScriptWord {
        ScriptWord(text: String(decoding: text, as: UTF8.self), substitutions: substitutions,
                   isWholeSubstitution: substitutions.count == 1 && literalCount == 0, isAssignment: assignment == .yes,
                   isQuoted: isQuoted)
    }
}

// MARK: - Bytes

enum ScriptBytes {
    /// Longest stretch of one line the lens examines; the rest of a longer line is ignored. Twice the
    /// default line budget (32 KiB), so a line the pipeline lets through is read to its end, and a
    /// caller with a larger budget still gets bounded work per line.
    static let lineLimit = 64 * 1024
    /// Marks the end of a cut line, so nothing opened on it (a quote, a substitution) stays open.
    static let cutMarker: UInt8 = 0

    /// Length of the line separator starting at `index`, or 0: LF, CR, CRLF, NEL, LINE SEPARATOR and
    /// PARAGRAPH SEPARATOR, exactly the separators `LogicalLines` numbers.
    @inline(__always)
    static func breakLength(in bytes: UnsafeBufferPointer<UInt8>, at index: Int) -> Int {
        guard index < bytes.count else { return 0 }
        switch bytes[index] {
        case 0x0A: return 1
        case 0x0D: return index + 1 < bytes.count && bytes[index + 1] == 0x0A ? 2 : 1
        case 0xC2: return index + 1 < bytes.count && bytes[index + 1] == 0x85 ? 2 : 0
        case 0xE2:
            return index + 2 < bytes.count && bytes[index + 1] == 0x80 && (bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9) ? 3 : 0
        default: return 0
        }
    }

    /// A copy with every line cut to `lineLimit` bytes and marked, or `nil` when no line is longer.
    static func limitingLines(of bytes: UnsafeBufferPointer<UInt8>) -> [UInt8]? {
        var needsCut = false
        var lineStart = 0
        var index = 0
        while index < bytes.count {
            let length = breakLength(in: bytes, at: index)
            if length > 0 {
                if index - lineStart > lineLimit { needsCut = true; break }
                index += length
                lineStart = index
            } else {
                index += 1
            }
        }
        guard needsCut || bytes.count - lineStart > lineLimit else { return nil }
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        lineStart = 0
        index = 0
        while index <= bytes.count {
            let length = index < bytes.count ? breakLength(in: bytes, at: index) : 1
            if length > 0 || index == bytes.count {
                let lineLength = index - lineStart
                result.append(contentsOf: bytes[lineStart..<(lineStart + min(lineLength, lineLimit))])
                if lineLength > lineLimit { result.append(cutMarker) }
                if index < bytes.count { result.append(contentsOf: bytes[index..<(index + length)]) }
                index += length
                lineStart = index
            } else {
                index += 1
            }
        }
        return result
    }
}
