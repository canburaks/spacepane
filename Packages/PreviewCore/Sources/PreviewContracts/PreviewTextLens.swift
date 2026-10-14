import Foundation

/// Reads the displayed, already concealed text of a text preview and reports what the file would do
/// or what it holds, as typed findings (decision 029). A lens never sees source bytes, never runs or
/// evaluates anything from the file, and never puts a source value into a finding: findings carry
/// kinds, counts, typed numbers and lines of the displayed text, exactly as decision 012 requires.
///
/// Lenses are attached to registrations (`AdapterRegistration.adding(lenses:)`) at the composition
/// boundary, so the pipeline depends only on this protocol. A lens decides for itself whether a file is
/// one it recognizes; most return no findings for most files and must stay cheap when they do.
public protocol PreviewTextLens: Sendable {
    /// - Parameters:
    ///   - text: the displayed text after the privacy filter, the text the line-number gutter numbers.
    ///   - request: metadata about the file; never its bytes.
    ///   - context: the request's budget, cancellation and deadline. Call `checkpoint()` in long loops.
    /// - Returns: findings whose `lines` are one-based logical lines of `text`.
    /// - Throws: only cancellation or the request deadline. Any other error drops this lens's findings
    ///   and leaves the preview untouched.
    func findings(in text: String, request: PreviewLensRequest, context: RequestContext) throws -> [PreviewFinding]
}

/// What a lens may know about a file besides its displayed text: identity and location metadata only.
public struct PreviewLensRequest: Equatable, Sendable {
    public let formatID: FormatID
    /// The last path component with its original case, for example `tasks.json` or `com.example.agent.plist`.
    public let fileName: String
    /// The name of the folder that holds the file, for example `.vscode` or `LaunchAgents`; `nil` at the root.
    /// It is read from the URL only, with no file access, and must never appear in a finding.
    public let parentDirectoryName: String?
    /// The adapter's source-language hint, when it gave one.
    public let sourceLanguage: SourceLanguageID?
    /// Where the displayed text comes from. Lenses are never called for app-made summaries.
    public let origin: TextOrigin

    public init(formatID: FormatID, fileName: String, parentDirectoryName: String? = nil,
                sourceLanguage: SourceLanguageID? = nil, origin: TextOrigin = .source) {
        self.formatID = formatID
        self.fileName = fileName
        self.parentDirectoryName = parentDirectoryName
        self.sourceLanguage = sourceLanguage
        self.origin = origin
    }
}
