import Foundation
import PreviewContracts

/// Comments are outside the structured field grammar. Conceal their whole content when
/// the shared secret-field policy recognizes an assignment, while retaining delimiters.
enum CommentPrivacyRanges {
    private static let assignment = try? NSRegularExpression(
        pattern: SecretFieldPolicy.assignmentPattern)

    static func sensitiveRange(in bytes: [UInt8], content: Range<Int>, context: RequestContext) throws -> SensitiveRange? {
        try context.checkpoint()
        guard !content.isEmpty else { return nil }
        guard let assignment else { return .init(utf8Range: content) }
        let source = String(decoding: bytes[content], as: UTF8.self)
        let nsSource = source as NSString
        var sensitive = false
        var failure: (any Error)?
        assignment.enumerateMatches(in: source, options: [.reportProgress],
                                    range: NSRange(location: 0, length: nsSource.length)) { match, _, stop in
            do { try context.checkpoint() }
            catch { failure = error; stop.pointee = true; return }
            if let match, SecretFieldPolicy.isSensitive(nsSource.substring(with: match.range(at: 1))) {
                sensitive = true
                stop.pointee = true
            }
        }
        if let failure { throw failure }
        try context.checkpoint()
        return sensitive ? .init(utf8Range: content) : nil
    }
}
