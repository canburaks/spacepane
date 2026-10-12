import Foundation

/// Where a leading prefix of an oversized text file may end so that every record it keeps is complete.
public enum PartialRecordBoundary: Sendable, Equatable {
    /// After any line terminator: plain text, source, logs, JSON Lines and INI files.
    case line
    /// After a blank line: caption formats whose cues are blank-line separated blocks.
    case blankLine
    /// After a line terminator that is outside a double-quoted field: CSV records may contain line breaks.
    case quotedRecord
}

/// The extra input a text adapter is prepared to receive. Adapters are strict by default: a file larger
/// than the request's input budget, or a line longer than its line budget, fails with a typed error.
/// An adapter opts in by conforming to `TextInputPolicyProviding`; the shared pipeline then offers it
/// the leading complete records of an oversized file, or the whole text with its long lines intact.
/// Structured formats (JSON, YAML, TOML, XML, property lists, notebooks) never opt into partial reads,
/// because a truncated document is not a valid one.
public struct TextInputPolicy: Sendable, Equatable {
    /// When set, a file larger than `maxInputBytes` is cut back to its last complete record before the
    /// adapter runs, and the presentation reports the full size. `nil` keeps `inputTooLarge`.
    public var partialBoundary: PartialRecordBoundary?
    /// Skips the per-line byte limit while decoding so an adapter that reformats (minified JSON) can
    /// decide. Binary control characters, line count and output size are still enforced.
    public var allowsLongLines: Bool
    public init(partialBoundary: PartialRecordBoundary? = nil, allowsLongLines: Bool = false) {
        self.partialBoundary = partialBoundary
        self.allowsLongLines = allowsLongLines
    }
    public static let strict = TextInputPolicy()
    public static func leadingRecords(_ boundary: PartialRecordBoundary = .line) -> TextInputPolicy {
        TextInputPolicy(partialBoundary: boundary)
    }
}

/// Declared by an adapter, never by a registration or the host: the pipeline asks the adapter that
/// it is about to run, so existing registrations stay unchanged and no host switches on a format.
public protocol TextInputPolicyProviding: FormatAdapter {
    var textInputPolicy: TextInputPolicy { get }
}

/// Readers that can return the leading bytes of a file larger than the input budget. The request
/// still owns cancellation and the no-follow, read-only descriptor; the reported total size lets the
/// presentation say how much of the file is shown. A reader that does not conform simply keeps the
/// strict behavior, so custom and test readers need no change.
public protocol LeadingBytesReading: PreviewFileReading {
    func readLeading(url: URL, context: RequestContext) throws -> FileBytes
}
