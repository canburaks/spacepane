import Foundation
import PreviewContracts

/// GitHub-style alert kinds. Several markup formats map their admonitions onto these five,
/// so one localized title and one color role serve every family.
enum MarkupAlertKind: String, CaseIterable, Hashable, Sendable {
    case note, tip, important, warning, caution
}

/// How one table column sits in its cells. `automatic` follows the cells: a column of numbers sits on its trailing
/// edge and anything else on its leading edge. A Markdown delimiter row (`:---`, `:-:`, `---:`) chooses the others.
enum MarkupColumnAlignment: Hashable, Sendable {
    case automatic, leading, center, trailing
}

/// One style span over the rendered text. Decorations only change fonts, colors, glyph
/// attributes and paragraph layout; they never add links, attachments or actions.
struct MarkdownDecoration: Equatable, Sendable {
    enum Style: Hashable, Sendable {
        case heading(Int), bold, italic, code, quote, tableHeader
        /// Whole-line code: fenced, verbatim or literal blocks. Left-to-right and never direction-tagged.
        case codeBlock
        /// A fenced diagram source (for example Mermaid) kept as code. Another view may later
        /// draw it; this model never interprets or renders the diagram.
        case diagramSource
        case strikethrough
        /// Inline and display math, an approximation in Unicode and never typeset output.
        case math, mathBlock
        case alertTitle(MarkupAlertKind)
        /// The leading bar of an alert, set on its title line and on each of its body lines. Only the bar's ink
        /// follows the kind; the text is the quote's text.
        case alertBar(MarkupAlertKind)
        /// A whole table: rows are lines and cells are separated by tabs. Styling measures the cells and sets tab
        /// stops from them, so the text, its tabs and what a copy yields never change.
        case table(columns: [MarkupColumnAlignment], hasHeader: Bool)
        case frontMatterBlock, frontMatterKey
        case footnoteMark, footnoteLabel
        /// A list item paragraph: nesting depth plus the marker width in characters for hanging indentation.
        case listItem(depth: Int, markerLength: Int)
        /// A continuation line of a list item: indented to the item's text, without a marker.
        case listContinuation(depth: Int, markerLength: Int)
        case taskMarker(done: Bool)
        case rule
        /// Source comments and other de-emphasized spans.
        case dimmed
        case definitionTerm
        /// Paragraphs whose first strong character is right-to-left.
        case rightToLeft
        case centered, trailing
        /// Left indentation in em units for paragraph-level layout such as screenplay dialogue.
        case indent(Int)
    }
    let range: NSRange
    let style: Style
}

/// A heading collected while rendering. `range` covers the title in the rendered text, so a
/// selection made from it reveals exactly the heading the reader chose.
struct MarkupHeading: Equatable, Sendable {
    let level: Int
    let title: String
    let range: NSRange
}

/// A kind of reference that a rendered document shows as inert text and the preview never loads. Only the
/// kind is recorded: a destination is classified from its spelling and then forgotten, so nothing about it can
/// reach a notice.
enum OmittedResourceKind: Equatable, Sendable {
    case remoteImage, localImage, linkedFile

    /// Longest prefix of a destination that is read to find its scheme. The inline readers' scan limit already
    /// bounds the destination itself, so classifying never widens a scan.
    private static let maximumSchemeScan = 64

    /// Classifies an image destination from its spelling alone; nothing is resolved, opened or requested.
    /// A URL scheme or a leading `//` makes it remote, except `file:`, which names a path on this Mac. A `data:`
    /// URL is embedded in the document, and an empty destination (the form converted ebooks and saved pages use,
    /// which keeps only the description) has nothing to load, so neither counts as omitted (nil). Anything else
    /// is a path on this Mac.
    static func image(destination: String) -> OmittedResourceKind? {
        var head = destination.prefix(maximumSchemeScan).drop(while: { $0.isWhitespace })
        // Markdown writes a destination that contains spaces between angle brackets.
        if head.first == "<" { head = head.dropFirst() }
        guard !head.isEmpty, head.first != ">" else { return nil }
        if head.hasPrefix("//") { return .remoteImage }
        if let colon = head.firstIndex(of: ":") {
            let scheme = head[..<colon]
            // One letter is a drive letter, not a scheme.
            if scheme.count > 1, scheme.first?.isLetter == true, scheme.allSatisfy(Self.isSchemeCharacter) {
                switch scheme.lowercased() {
                case "data": return nil
                case "file": return .localImage
                default: return .remoteImage
                }
            }
        }
        return .localImage
    }

    private static func isSchemeCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || "+-.".contains(character))
    }
}

/// How many references of each kind a rendered document left as inert text. The status line says so only when
/// something was left out, instead of claiming it for every document.
struct OmittedResources: Equatable, Sendable {
    var remoteImages = 0
    var localImages = 0
    var linkedFiles = 0

    var isEmpty: Bool { remoteImages == 0 && localImages == 0 && linkedFiles == 0 }
    /// Images of either kind, which the status line counts together.
    var images: Int { remoteImages + localImages }

    mutating func note(_ kind: OmittedResourceKind) {
        switch kind {
        case .remoteImage: remoteImages += 1
        case .localImage: localImages += 1
        case .linkedFile: linkedFiles += 1
        }
    }

    mutating func add(_ other: OmittedResources) {
        remoteImages += other.remoteImages
        localImages += other.localImages
        linkedFiles += other.linkedFiles
    }
}

extension OmittedResources {
    /// One reference of `kind`.
    init(_ kind: OmittedResourceKind) {
        self.init()
        note(kind)
    }
}

/// One explicit emitted code body in final already-concealed rendered text. The UTF-16 range
/// includes its actual LF/blank lines, excluding fences, info text, labels and block separators.
/// Zero-length bodies have no entry. A language is a recognized semantic hint, never a raw label.
struct MarkupCodeBlock: Equatable, Sendable {
    let range: NSRange
    let language: SourceLanguageID?

    /// Canonical hints only; the Formats alias table is intentionally not copied into this module.
    /// Stop after one bounded token, and never turn a truncated or filtered unknown word into a hint.
    static func recognizedLanguage(inFenceInfo info: String) -> SourceLanguageID? {
        var word: [UInt8] = []
        for scalar in info.unicodeScalars {
            if CharacterSet.whitespaces.contains(scalar) || scalar == "{" { break }
            let value = scalar.value
            guard word.count < 32, value < 128,
                  (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value)
                    || "_+#.-".unicodeScalars.contains(scalar) else { return nil }
            word.append(UInt8(value))
        }
        guard !word.isEmpty else { return nil }
        let token = String(decoding: word, as: UTF8.self).lowercased()
        return SourceLanguageID.all.first { $0.rawValue == token }
    }
}

/// One explicitly emitted Mermaid fence, including an empty body. No raw language labels are retained.
struct MarkupDiagramFence: Equatable, Sendable {
    let range: NSRange
}

/// Rendered text of one document with its decorations and headings. Every renderer in the
/// markup family produces this same model from already-concealed text.
struct SafeMarkdownDocument: Equatable, Sendable {
    let text: String
    let decorations: [MarkdownDecoration]
    var headings: [MarkupHeading] = []
    /// What the document points at and the preview did not load, counted by the renderer that left it out.
    var omitted = OmittedResources()
    /// Only producers that know a complete emission boundary record these; never infer them from styles.
    var codeBlocks: [MarkupCodeBlock] = []
    var diagramFences: [MarkupDiagramFence] = []
}
