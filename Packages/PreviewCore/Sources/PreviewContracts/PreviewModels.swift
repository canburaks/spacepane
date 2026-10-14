import Foundation

public enum TextEncoding: String, Sendable {
    case utf8, utf16LittleEndian, utf16BigEndian
    /// IBM PC code page 437, decoded by a dedicated legacy text-art adapter.
    case codePage437
}

/// An adapter supplies a rendering hint; tokenization consumes only privacy-filtered text.
public enum TextSyntax: String, Sendable {
    case plain, json, sourceCode, yaml, toml, environment, markdown, diff, xml, propertyList, strings
    /// Delimited tables and timed captions; safe derived views interpret only concealed text.
    case commaSeparated, tabSeparated, subRip, webVTT
    // Code and configuration breadth: logs, INI-style files, JSON with comments, more caption formats.
    case log, ini, jsonWithComments
    case subStationAlpha, timedText, subViewer, lyrics, microDVD
    // Markup documents rendered through the same inert decoration model as Markdown.
    case latex, bibtex, asciidoc, restructuredText, orgMode, fountain
    // Diagram sources whose safe text a native diagram view interprets.
    case mermaid, drawio
    // [workstream syntax additions] Add any further case on its own line below your marker.
    // [code]
    // [markup]
    // [diagrams]
    // [data]
    // [packages]
    // [ebooks]
}

/// A semantic source-language hint, independent of format identity. Adapters derive it from
/// the request's name hint; renderers use it only to choose lexical decoration rules.
public struct SourceLanguageID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Encoded raster bytes taken from a document: a cover, a comic page or an icon. Adapters bound
/// and validate the container and dimensions but never decode pixels; renderers decode lazily
/// through ImageIO with an explicit pixel bound. Images never pass through text concealment,
/// so adapters must not extract images from formats whose pictures can carry secrets as text.
public struct PreviewImage: Equatable, Sendable {
    public enum Role: String, Sendable { case cover, page, icon, figure }
    public static let maximumPixelDimension = 16_384
    public let data: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let role: Role
    // No adapter-chosen label: a page's archive path or file name is document text that would bypass
    // concealment; views name pages by position through localized strings (decision 027, Q-02).
    public init(data: Data, pixelWidth: Int, pixelHeight: Int, role: Role) {
        self.data = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.role = role
    }
    public var isValid: Bool {
        !data.isEmpty && (1...Self.maximumPixelDimension).contains(pixelWidth)
        && (1...Self.maximumPixelDimension).contains(pixelHeight)
    }
}

/// Where a presentation's `text` comes from. Renderers label the text mode from it and thumbnails
/// decide what may be drawn from it; it never carries a source value.
public enum TextOrigin: String, Equatable, Sendable {
    /// The file's own decoded, concealed characters.
    case source
    /// The file's structure regenerated as text in the same language (a minified document shown pretty-printed).
    case reformatted
    /// Another representation turned into text (an ebook or web archive as Markdown, a property list as
    /// JSON, a draw.io page as normalized XML).
    case converted
    /// An app-made description of a binary, database or container; never the file's text.
    case summary
}

public struct TextPresentation: Equatable, Sendable {
    public let formatID: FormatID
    public let text: String
    public let lineCount: Int
    public let byteCount: Int
    public let encoding: TextEncoding
    public let redactionCount: Int
    public let syntax: TextSyntax
    public let midi: MIDIPresentation?
    public let invalidRecordLines: [Int]
    /// Original record count allows safe views to detect line collapse during concealment.
    public let sourceRecordCount: Int?
    public let sourceLanguage: SourceLanguageID?
    public let images: [PreviewImage]
    /// Size of the whole source file when only its leading complete lines are shown; `nil` when the
    /// presentation covers the entire file. `byteCount` then counts the bytes that are shown.
    public let truncatedSourceBytes: Int?
    /// `true` when the text was regenerated from the parsed structure (a minified document shown
    /// pretty-printed) instead of being the decoded source characters.
    public let isReformatted: Bool
    /// Normalized typed findings; lines refer to `text`, the concealed displayed text.
    public let findings: [PreviewFinding]
    /// Whether `text` is the file's own text or app-made; see `TextOrigin`.
    public let origin: TextOrigin
    /// Value-free parser counts; headers and cell values never enter this contract.
    public let facts: PresentationFacts
    public init(formatID: FormatID, text: String, lineCount: Int, byteCount: Int,
                encoding: TextEncoding, redactionCount: Int, syntax: TextSyntax = .plain,
                midi: MIDIPresentation? = nil, invalidRecordLines: [Int] = [], sourceRecordCount: Int? = nil,
                sourceLanguage: SourceLanguageID? = nil, images: [PreviewImage] = [],
                truncatedSourceBytes: Int? = nil, isReformatted: Bool = false, findings: [PreviewFinding] = [],
                origin: TextOrigin = .source, facts: PresentationFacts = .none) {
        self.formatID = formatID
        self.text = text
        self.lineCount = lineCount
        self.byteCount = byteCount
        self.encoding = encoding
        self.redactionCount = redactionCount
        self.syntax = syntax
        self.midi = midi
        self.invalidRecordLines = invalidRecordLines
        self.sourceRecordCount = sourceRecordCount
        self.sourceLanguage = sourceLanguage
        self.images = images
        self.truncatedSourceBytes = truncatedSourceBytes
        self.isReformatted = isReformatted
        self.findings = findings
        self.origin = origin
        self.facts = facts
    }

    /// Display invalidation must preserve the safe source's exact code units. Swift String equality
    /// intentionally folds canonically equivalent Unicode, which can otherwise leave stale text,
    /// selections and derived outlines behind when a same-generation live reload replaces the source.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.formatID == rhs.formatID && lhs.text.utf16.elementsEqual(rhs.text.utf16)
            && lhs.lineCount == rhs.lineCount && lhs.byteCount == rhs.byteCount
            && lhs.encoding == rhs.encoding && lhs.redactionCount == rhs.redactionCount
            && lhs.syntax == rhs.syntax && lhs.midi == rhs.midi
            && lhs.invalidRecordLines == rhs.invalidRecordLines && lhs.sourceRecordCount == rhs.sourceRecordCount
            && lhs.sourceLanguage == rhs.sourceLanguage && lhs.images == rhs.images
            && lhs.truncatedSourceBytes == rhs.truncatedSourceBytes && lhs.isReformatted == rhs.isReformatted
            && lhs.findings == rhs.findings && lhs.origin == rhs.origin && lhs.facts == rhs.facts
    }
}

public enum PreviewFailure: Error, Equatable, Sendable {
    case unsupportedFormat, missingFile, unreadableFile, notRegularFile, unavailableContent
    case inputTooLarge, outputTooLarge, binaryContent, unsupportedEncoding, malformedDocument
    case cadImporterUnavailable
    /// Encrypted members, headers or DRM-protected content; never decrypted or guessed.
    case encryptedContent
    case structureTooDeep, tooManyNodes, tooManyLines, lineTooLong, invalidBudget, deadlineExceeded
    /// A recognized type whose particular variant has no parser (a versioned or compressed sub-format);
    /// distinct from `unsupportedFormat` so the message can say the type itself is known.
    case unsupportedVariant
    /// A mesh beyond `GeometryLimits`; distinct from `tooManyNodes` so the message can name the geometry limit.
    case geometryTooComplex
}

public enum PreviewOutcome: Equatable, Sendable {
    case ready(TextPresentation)
    case geometryReady(GeometryPresentation)
    case disabledByUser(FormatID)
    case unavailable(PreviewFailure)
    case cancelled
}

public enum PreviewInspection: Equatable, Sendable {
    case enabled(FormatID)
    case disabledByUser(FormatID)
    case unsupported
    /// Source classification was refused or failed before content work.
    case unavailable(PreviewFailure)
}

public struct PreviewBudget: Equatable, Sendable {
    public let maxInputBytes: Int
    public let maxOutputUTF8Bytes: Int
    public let maxJSONDepth: Int
    public let maxJSONNodes: Int
    public let maxTextLines: Int
    public let maxLineUTF8Bytes: Int
    public let maxMilliseconds: Int

    public init(maxInputBytes: Int = 1_048_576, maxOutputUTF8Bytes: Int = 2_097_152,
                maxJSONDepth: Int = 64, maxJSONNodes: Int = 20_000, maxTextLines: Int = 20_000,
                maxLineUTF8Bytes: Int = 32_768, maxMilliseconds: Int = 2_000) {
        self.maxInputBytes = maxInputBytes
        self.maxOutputUTF8Bytes = maxOutputUTF8Bytes
        self.maxJSONDepth = maxJSONDepth
        self.maxJSONNodes = maxJSONNodes
        self.maxTextLines = maxTextLines
        self.maxLineUTF8Bytes = maxLineUTF8Bytes
        self.maxMilliseconds = maxMilliseconds
    }
    public static let standard = PreviewBudget()
    /// Containers read members, directories and compressed streams rather than display their bytes.
    /// Random-access sources charge every byte read against `maxInputBytes`; whole-stream formats
    /// (GZIP, bzip2, xz) read at most this much. Output, node and line limits stay standard.
    public static let containerScan = PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 5_000)
    public var isValid: Bool {
        (1...16_777_216).contains(maxInputBytes) && (1...33_554_432).contains(maxOutputUTF8Bytes)
        && (1...128).contains(maxJSONDepth) && (1...1_000_000).contains(maxJSONNodes)
        && (1...100_000).contains(maxTextLines) && (1...1_048_576).contains(maxLineUTF8Bytes)
        && (1...30_000).contains(maxMilliseconds)
    }
}

/// Metadata-only naming facts about the previewed item. Adapters may use them for semantic
/// hints (such as a source language) but never to reopen, list or read sibling paths.
public struct PreviewNameHint: Equatable, Sendable {
    /// Lowercased last path component.
    public let filename: String
    /// Lowercased final suffix without the dot; empty when the name has none.
    public let suffix: String
    public init(filename: String, suffix: String) {
        self.filename = filename.lowercased()
        self.suffix = suffix.lowercased()
    }
    public init(url: URL) { self.init(filename: url.lastPathComponent, suffix: url.pathExtension) }
}

/// Request-scoped choices derived from the immutable preference snapshot by the pipeline.
/// Adapters read them; they never read preferences or storage themselves.
public struct PreviewRequestOptions: Equatable, Sendable {
    public static let folderDepthRange = 1...4
    /// Directory levels a folder summary may enumerate; 1 lists immediate children only.
    public var folderDepth: Int
    /// Whether names starting with a dot are listed in folder summaries.
    public var includesHiddenItems: Bool
    public init(folderDepth: Int = 1, includesHiddenItems: Bool = false) {
        self.folderDepth = min(max(folderDepth, Self.folderDepthRange.lowerBound), Self.folderDepthRange.upperBound)
        self.includesHiddenItems = includesHiddenItems
    }
}

public struct RequestContext: Sendable {
    public let budget: PreviewBudget
    public var sourceReadPolicy: SourceReadPolicy = .regularFile
    public var nameHint: PreviewNameHint?
    public var options = PreviewRequestOptions()
    /// Package-only test seam, run first at every checkpoint so a test can request cancellation
    /// at an exact point inside an active synchronous parse instead of racing a sleep. App and
    /// extension targets cannot see it, and production composition never sets it.
    package var checkpointObserver: (@Sendable () -> Void)?
    private let deadline: ContinuousClock.Instant
    public init(budget: PreviewBudget) {
        self.budget = budget
        deadline = ContinuousClock.now.advanced(by: .milliseconds(budget.maxMilliseconds))
    }
    public func checkpoint() throws {
        checkpointObserver?()
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw PreviewFailure.deadlineExceeded }
    }
}

public struct FileBytes: Sendable {
    public let data: Data
    /// Size of the source file when `data` holds only its leading bytes; `nil` for a complete read.
    public let totalByteCount: Int?
    public init(data: Data, totalByteCount: Int? = nil) {
        self.data = data
        self.totalByteCount = totalByteCount
    }
}

public protocol PreviewFileReading: Sendable {
    func read(url: URL, context: RequestContext) throws -> FileBytes
    func openRandomAccess(url: URL, context: RequestContext) throws -> any PreviewByteSource
}

public extension PreviewFileReading {
    func openRandomAccess(url: URL, context: RequestContext) throws -> any PreviewByteSource {
        throw PreviewFailure.unsupportedFormat
    }
}

public struct DecodedText: Sendable {
    public let text: String
    public let encoding: TextEncoding
    public let byteCount: Int
    /// Retains source provenance when shared decoding consumes an encoding marker.
    public let hasByteOrderMark: Bool
    public init(text: String, encoding: TextEncoding, byteCount: Int, hasByteOrderMark: Bool = false) {
        self.text = text
        self.encoding = encoding
        self.byteCount = byteCount
        self.hasByteOrderMark = hasByteOrderMark
    }
}

/// UTF-8 offsets, used only inside parsing/privacy. Never exposed as a raw-source UI mode.
public struct SensitiveRange: Sendable {
    public let utf8Range: Range<Int>
    public init(utf8Range: Range<Int>) { self.utf8Range = utf8Range }
}

public struct ParsedTextDocument: Sendable {
    public let text: String
    public let sensitiveRanges: [SensitiveRange]
    public let usesStructuredPrivacy: Bool
    public let syntax: TextSyntax
    public let midi: MIDIPresentation?
    public let invalidRecordLines: [Int]
    /// Original record count allows safe views to detect line collapse during concealment.
    public let sourceRecordCount: Int?
    /// Source encoding reported by a binary adapter that decoded the bytes itself. `nil`
    /// means the adapter did not decode text and the pipeline reports its UTF-8 default.
    public let decodedEncoding: TextEncoding?
    public let sourceLanguage: SourceLanguageID?
    /// Bounded encoded images; see `PreviewImage` for the privacy and decoding contract.
    public let images: [PreviewImage]
    /// Set by an adapter that regenerated `text` from the parsed structure; see `TextPresentation`.
    public let isReformatted: Bool
    /// Facts the adapter found while parsing. They carry no source values; any lines must refer
    /// to text that concealment cannot shift, otherwise leave `lines` empty.
    public let findings: [PreviewFinding]
    /// Whether `text` is the file's own text or app-made; adapters that write summaries or
    /// conversions say so, and the pipeline carries it into the presentation unchanged.
    public let origin: TextOrigin
    /// Value-free facts accumulated during the existing bounded parse.
    public let facts: PresentationFacts
    public init(text: String, sensitiveRanges: [SensitiveRange] = [], usesStructuredPrivacy: Bool = false,
                syntax: TextSyntax = .plain, midi: MIDIPresentation? = nil, invalidRecordLines: [Int] = [], sourceRecordCount: Int? = nil,
                decodedEncoding: TextEncoding? = nil, sourceLanguage: SourceLanguageID? = nil, images: [PreviewImage] = [],
                isReformatted: Bool = false, findings: [PreviewFinding] = [], origin: TextOrigin = .source,
                facts: PresentationFacts = .none) {
        self.text = text
        self.sensitiveRanges = sensitiveRanges
        self.usesStructuredPrivacy = usesStructuredPrivacy
        self.syntax = syntax
        self.midi = midi
        self.invalidRecordLines = invalidRecordLines
        self.sourceRecordCount = sourceRecordCount
        self.decodedEncoding = decodedEncoding
        self.sourceLanguage = sourceLanguage
        self.images = images
        self.isReformatted = isReformatted
        self.findings = findings
        self.origin = origin
        self.facts = facts
    }
}

public protocol FormatAdapter: Sendable {
    func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument
}

public enum AdapterInputPath: Sendable {
    case geometry(@Sendable () -> any GeometryFormatAdapter)
    case text(@Sendable () -> any FormatAdapter)
    case binary(@Sendable () -> any BinaryFormatAdapter)
    case url(@Sendable () -> any URLFormatAdapter)
    case randomAccess(@Sendable () -> any RandomAccessFormatAdapter)
}

public enum SourceReadPolicy: Sendable {
    case regularFile, sqliteSnapshot, directory
}

/// A genuinely zero-byte source can be shown as empty without asking a structured parser to invent
/// a document. Binary families opt in explicitly; missing/truncated bytes never qualify.
public enum EmptyInputPolicy: Equatable, Sendable {
    case parse, emptyPreview
}

public struct AdapterRegistration: Sendable {
    public let formatID: FormatID
    public let inputPath: AdapterInputPath
    public let sourcePolicy: SourceReadPolicy
    public let defaultBudget: PreviewBudget?
    public let emptyInputPolicy: EmptyInputPolicy
    /// Lenses that read this format's displayed text after concealment (decision 029). Empty by default.
    public private(set) var lenses: [any PreviewTextLens] = []

    /// The same registration with `lenses` appended, for the composition boundary.
    public func adding(lenses added: [any PreviewTextLens]) -> AdapterRegistration {
        var copy = self
        copy.lenses += added
        return copy
    }

    public init(formatID: FormatID, defaultBudget: PreviewBudget,
                geometryAdapter: @escaping @Sendable () -> any GeometryFormatAdapter) {
        self.formatID = formatID
        self.inputPath = .geometry(geometryAdapter)
        self.sourcePolicy = .regularFile
        self.defaultBudget = defaultBudget
        self.emptyInputPolicy = .parse
    }
    public init(formatID: FormatID, emptyInputPolicy: EmptyInputPolicy = .emptyPreview,
                makeAdapter: @escaping @Sendable () -> any FormatAdapter) {
        self.defaultBudget = nil
        self.formatID = formatID
        self.inputPath = .text(makeAdapter)
        self.sourcePolicy = .regularFile
        self.emptyInputPolicy = emptyInputPolicy
    }
    public init(formatID: FormatID, sourcePolicy: SourceReadPolicy = .regularFile, defaultBudget: PreviewBudget? = nil,
                emptyInputPolicy: EmptyInputPolicy = .parse,
                binaryAdapter: @escaping @Sendable () -> any BinaryFormatAdapter) {
        self.defaultBudget = defaultBudget
        self.formatID = formatID
        self.inputPath = .binary(binaryAdapter)
        self.sourcePolicy = sourcePolicy
        self.emptyInputPolicy = emptyInputPolicy
    }
    public init(formatID: FormatID, urlAdapter: @escaping @Sendable () -> any URLFormatAdapter) {
        self.defaultBudget = nil
        self.formatID = formatID
        self.inputPath = .url(urlAdapter)
        self.sourcePolicy = .directory
        self.emptyInputPolicy = .parse
    }
    public init(formatID: FormatID, defaultBudget: PreviewBudget? = nil,
                randomAccessAdapter: @escaping @Sendable () -> any RandomAccessFormatAdapter) {
        self.defaultBudget = defaultBudget
        self.formatID = formatID
        self.inputPath = .randomAccess(randomAccessAdapter)
        self.sourcePolicy = .regularFile
        self.emptyInputPolicy = .parse
    }
}

public struct SafeText: Sendable {
    public let text: String
    public let redactionCount: Int
    public let syntax: TextSyntax
    /// Facts the privacy stage found, such as the kinds of concealed secrets. Lines refer to `text`.
    public let findings: [PreviewFinding]
    public init(text: String, redactionCount: Int, syntax: TextSyntax = .plain, findings: [PreviewFinding] = []) {
        self.text = text
        self.redactionCount = redactionCount
        self.syntax = syntax
        self.findings = findings
    }
}

public protocol PreviewPrivacyFiltering: Sendable {
    func filter(_ document: ParsedTextDocument, context: RequestContext) throws -> SafeText
}

/// Shared semantic classification; formats may annotate values but cannot change privacy defaults.
public enum SecretFieldPolicy {
    /// What the privacy stage writes in place of each concealed value. Safe views recognize it to
    /// keep concealed values out of derived output such as table profiles.
    public static let concealmentToken = "••••"
    /// Invisible characters that can sit inside a key name without changing how it looks: format
    /// characters (zero-width, direction controls, soft hyphen, Unicode Tags), the combining grapheme
    /// joiner and variation selectors. Key patterns accept them as key characters (ICU class syntax)
    /// and `isSensitive` ignores them, so `pass<ZWSP>word` is still a password field.
    public static let invisibleKeyCharacterClass = #"\p{Cf}\x{034F}\x{FE00}-\x{FE0F}\x{E0100}-\x{E01EF}"#
    /// The plain-text assignment heuristic shared by the privacy filter and structured adapters:
    /// an identifier, optional quotes, then `:` or `=`. The identifier boundary prevents repeated
    /// greedy retries along one long token.
    public static let assignmentPattern =
        #"(?i)(?<![a-z0-9_.\#(invisibleKeyCharacterClass)-])[\"']?([a-z_\#(invisibleKeyCharacterClass)][a-z0-9_.\#(invisibleKeyCharacterClass)-]*)[\"']?[\t ]*[:=]"#

    private static let credentialWords: Set<String> = [
        "password", "passwd", "pwd", "pass", "passphrase", "secret", "token", "auth",
        "authorization", "credential", "credentials", "cookie", "session", "dsn", "mnemonic", "tokens",
        // One-time-code seeds (decision 029): `login_totp`, `totp`, `otpauth` hold the secret that makes every code.
        "totp", "hotp", "otp", "otpauth"
    ]
    private static let compoundCredentialNames: Set<String> = [
        "apikey", "accesskey", "privatekey", "secretkey", "clientsecret", "signingkey", "encryptionkey",
        "masterkey", "clientkey", "keydata", "accesstoken", "refreshtoken", "awssecretaccesskey",
        "awsaccesskeyid", "connectionstring", "requirepass", "masterauth", "sessionid"
    ]
    /// Reserved plural-format metadata is structural. Only these complete names are exempt;
    /// an additional credential word, or a recognizable credential value, is still concealed.
    private static let ordinaryStructuralNames: Set<String> = [
        "nsstringlocalizedformatkey", "nsstringformatspectypekey", "nsstringformatvaluetypekey"
    ]

    /// Role in one object/item/element's name/value binding. The parser owns scope and order;
    /// identifiers such as id never turn an unrelated value member into a credential.
    public enum NamedValueRole: Equatable, Sendable { case name, value }
    public static func namedValueRole(_ member: String) -> NamedValueRole? {
        guard let tokens = keyTokens(member), tokens.count == 1 else { return nil }
        switch tokens[0] {
        case "name", "key": return .name
        case "value": return .value
        default: return nil
        }
    }

    public static func isSensitive(_ key: String) -> Bool {
        // Classification is bounded even for a malicious key made of millions of separators. A
        // name too large to classify is concealed; it must never allocate an unbounded token list.
        guard let tokens = keyTokens(key) else { return true }
        // nginx's proxy_pass is a routing directive, not a password. Keep the exact ordinary
        // directive compatible; an additional credential token still makes the field sensitive.
        if tokens == ["proxy", "pass"] { return false }
        if tokens.contains(where: credentialWords.contains) { return true }
        let compact = tokens.joined()
        if ordinaryStructuralNames.contains(compact) { return false }
        // Established compound names without separators remain compatible. These are complete
        // names, not substrings: passwordless, tokenizer, secretariat and compass remain ordinary.
        if compoundCredentialNames.contains(compact) {
            return true
        }
        for pair in zip(tokens, tokens.dropFirst()) {
            if pair.1 == "key", ["api", "access", "private", "secret", "signing", "encryption", "master", "client"].contains(pair.0) {
                return true
            }
            if pair.0 == "key", pair.1 == "data" { return true }
        }
        let words = tokens.filter { !$0.allSatisfy(\.isNumber) }
        // D13 broadens compound *_key names. A bare structural key (including numbered key0)
        // is used by JSON, property lists and ordinary configuration records, not a credential.
        guard words.count > 1, words.last == "key" else { return false }
        // The suffix allows prefixes such as ssh_public_key without turning an unrelated record
        // identifier into a credential. A credential word above still wins over this allowlist.
        return !["public", "primary", "foreign", "sort", "partition", "hot"].contains(words[words.count - 2])
    }

    /// Split only visible field names. Unicode scalar categories retain international letters;
    /// acronym/camel-case boundaries make APIKey and accessKey equivalent to api_key/access_key.
    private static func keyTokens(_ key: String) -> [String]? {
        var visible: [Unicode.Scalar] = []
        var examined = 0
        for scalar in key.unicodeScalars {
            guard examined < 1_024 else { return nil }
            examined += 1
            if isInvisibleKeyScalar(scalar) { continue }
            guard visible.count < 512 else { return nil }
            visible.append(scalar)
        }
        var tokens: [String] = []
        var token = ""
        for (index, scalar) in visible.enumerated() {
            let category = scalar.properties.generalCategory
            let letter = CharacterSet.letters.contains(scalar)
            let number = CharacterSet.decimalDigits.contains(scalar)
            if !letter && !number {
                if !token.isEmpty { tokens.append(token.lowercased()); token = "" }
            } else {
                if index > 0, !token.isEmpty {
                    let previous = visible[index - 1].properties.generalCategory
                    let next = index + 1 < visible.count ? visible[index + 1].properties.generalCategory : nil
                    let camel = category == .uppercaseLetter && previous == .lowercaseLetter
                    let acronym = category == .uppercaseLetter && previous == .uppercaseLetter && next == .lowercaseLetter
                    let digit = (category == .decimalNumber) != (previous == .decimalNumber)
                    if camel || acronym || digit { tokens.append(token.lowercased()); token = "" }
                }
                token.unicodeScalars.append(scalar)
            }
            guard tokens.count < 64 else { return nil }
        }
        if !token.isEmpty { tokens.append(token.lowercased()) }
        return tokens
    }

    /// The scalars `invisibleKeyCharacterClass` names.
    static func isInvisibleKeyScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .format || scalar.value == 0x034F
            || (0xFE00...0xFE0F).contains(scalar.value) || (0xE0100...0xE01EF).contains(scalar.value)
    }
}
