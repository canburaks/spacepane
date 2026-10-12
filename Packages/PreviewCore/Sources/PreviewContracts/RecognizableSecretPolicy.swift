import Foundation

/// Shared, UI-free credential-value recognition. Parsers inspect decoded strings through the Boolean
/// operation and annotate their original byte spans; the concealment stage uses ranges and kinds.
/// No operation returns or records a source value, performs I/O, or validates a credential remotely.
/// Callers supply text already bounded by their input/expansion policy. The policy checks cancellation,
/// deadlines and match storage; it does not charge an input ledger or reject raw text merely because
/// its size exceeds the safe-output budget (concealment can legitimately reduce that text).
public enum RecognizableSecretPolicy {
    public struct Match: Equatable, Sendable {
        public let utf16Range: Range<Int>
        public let kind: PreviewFindingKind
    }

    public enum Recognition: Equatable, Sendable {
        case matches([Match])
        /// Callers must conceal their bounded input instead of using an incomplete set of ranges.
        case matchLimitExceeded
    }

    /// Matches are unmerged and follow grammar-table order, preserving the filter's match accounting.
    /// The allowance cannot exceed the request's node budget; zero means any match exceeds it.
    public static func recognizedRanges(in text: String, context: RequestContext,
                                        maximumMatches: Int) throws -> Recognition {
        guard maximumMatches >= 0, maximumMatches <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
        var matches: [Match] = []
        var exceeded = false
        try scan(in: text, context: context) { match, _ in
            guard matches.count < maximumMatches else { exceeded = true; return false }
            matches.append(match)
            return true
        }
        return exceeded ? .matchLimitExceeded : .matches(matches)
    }

    /// Stops on the first validated match. It does not build a range list for a decoded string.
    public static func containsCredential(in text: String, context: RequestContext) throws -> Bool {
        var found = false
        try scan(in: text, context: context) { _, _ in found = true; return false }
        return found
    }

    /// Whether decoded credentials need concealment of their entire original value. Existing
    /// source-visible URL user-info keeps its precise concealment and readable host; a newly decoded
    /// URL/credential, additional escaped duplicate, uncertain allowance or any other grammar keeps
    /// the conservative whole-value annotation. Fragment code units exist only in this bounded call,
    /// are never returned, logged or cached, and use exact equality rather than String normalization.
    public static func requiresDecodedConcealment(in decodedText: String, originalText: String,
                                                  context: RequestContext) throws -> Bool {
        var visibleURLFragments: [[UInt16]: Int] = [:]
        var visibleCount = 0
        var exceeded = false
        let original = originalText as NSString
        try scan(in: originalText, context: context, visibleURLContextOnly: true) { match, _ in
            guard visibleCount < context.budget.maxJSONNodes else { exceeded = true; return false }
            visibleCount += 1
            let fragment = Array(original.substring(with: NSRange(match.utf16Range)).utf16)
            visibleURLFragments[fragment, default: 0] += 1
            return true
        }
        if exceeded { return true }
        let decoded = decodedText as NSString
        var examined = 0
        var requiresConcealment = false
        try scan(in: decodedText, context: context) { match, preservesVisibleURLContext in
            guard examined < context.budget.maxJSONNodes else { requiresConcealment = true; return false }
            examined += 1
            guard preservesVisibleURLContext else { requiresConcealment = true; return false }
            let fragment = Array(decoded.substring(with: NSRange(match.utf16Range)).utf16)
            guard let available = visibleURLFragments[fragment], available > 0 else {
                requiresConcealment = true; return false
            }
            visibleURLFragments[fragment] = available - 1
            return true
        }
        return requiresConcealment
    }

    private static let progressCheckpointMask = 0x3FF

    private enum ValueValidation: Equatable, Sendable {
        case unconditional, basicAuthorization, bearerAuthorization, encodedPrivateKey
    }

    /// Foundation documents NSRegularExpression as immutable/thread-safe. Each compiled instance
    /// is reused against an immutable request-local string; no mutable match state is shared.
    private struct ValuePattern: Sendable {
        let regex: NSRegularExpression?
        let source: PreviewFindingKind
        let requiredLiterals: [String]
        let concealedGroup: Int
        let validation: ValueValidation
        let preservesVisibleURLContext: Bool

        init(pattern: String, source: PreviewFindingKind, requiredLiterals: [String],
             concealedGroup: Int = 0, validation: ValueValidation = .unconditional,
             preservesVisibleURLContext: Bool = false) {
            let compiled = try? NSRegularExpression(pattern: pattern)
            let needsTokenGroup = validation == .basicAuthorization || validation == .bearerAuthorization
            let neededGroups = max(concealedGroup, needsTokenGroup ? 1 : 0)
            // An invalid internal grammar or capture index fails with a typed parser failure when
            // used, instead of a trap or an unchecked regular-expression error containing text.
            self.regex = concealedGroup >= 0 && (compiled?.numberOfCaptureGroups ?? -1) >= neededGroups ? compiled : nil
            self.source = source
            self.requiredLiterals = requiredLiterals
            self.concealedGroup = concealedGroup
            self.validation = validation
            self.preservesVisibleURLContext = preservesVisibleURLContext
        }
    }

    private static let valuePatterns = [
        ValuePattern(pattern: #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|\z)"#,
                     source: .secretPrivateKey, requiredLiterals: ["-----BEGIN "]),
        ValuePattern(pattern: #"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#, source: .secretCloudAccessKey, requiredLiterals: ["AKIA", "ASIA"]),
        ValuePattern(pattern: #"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"#, source: .secretCodeHostingToken,
                     requiredLiterals: ["ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_"]),
        ValuePattern(pattern: #"\bsk-[A-Za-z0-9_-]{16,}\b"#, source: .secretAPIKey, requiredLiterals: ["sk-"]),
        ValuePattern(pattern: #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#, source: .secretWebToken,
                     requiredLiterals: ["eyJ"]),
        // Case-insensitive matching has Unicode folding rules, so these patterns are never skipped.
        // Credential shape checks keep "basic programming" and "bearer certificates" readable.
        ValuePattern(pattern: #"(?i)\bbasic[\t ]+([A-Za-z0-9+/=]{8,})"#, source: .secretAuthorizationHeader,
                     requiredLiterals: [], validation: .basicAuthorization),
        ValuePattern(pattern: #"(?i)\bbearer[\t ]+([A-Za-z0-9_+/=.-]{8,})"#, source: .secretAuthorizationHeader,
                     requiredLiterals: [], validation: .bearerAuthorization),
        // The user information of `scheme://user:password@host`, for every format, structured ones included. Only
        // that part is concealed (group 1), so the scheme, host and path stay readable and a quoted value stays well
        // formed. `scheme://user@host` holds no password and is left alone; `scheme://:password@host` (an empty user,
        // as Redis URLs write it) is concealed. A scheme character must precede `://`. The authority ends at the first
        // `/ ? #`, whitespace, quote, bracket or list separator, and the last `@` before that ends the user
        // information, so a password may itself contain `@`. The required literal `://` skips the scan for a document
        // without one. A concealed match is a sensitive field, the finding the code, log and INI adapters reported
        // when each ran its own recognizer, so no finding kind is added.
        ValuePattern(pattern: #"(?<=[A-Za-z0-9+.-])://([^ \t\n\r/?#"'<>)\]},;@:]*:[^ \t\n\r/?#"'<>)\]},;]*)@"#,
                     source: .secretSensitiveField, requiredLiterals: ["://"], concealedGroup: 1,
                     preservesVisibleURLContext: true),
        // Additional grammars use the existing sensitive-value finding; recognizing a prefix
        // never validates a token, contacts its provider or exposes its value in metadata.
        ValuePattern(pattern: #"(?<![A-Za-z0-9_])(?:[rs]k_(?:live|test)_|sk_org_)[A-Za-z0-9_]{16,}"#,
                     source: .secretSensitiveField, requiredLiterals: ["sk_test_", "sk_live_", "rk_test_", "rk_live_", "sk_org_"]),
        ValuePattern(pattern: #"(?<![A-Za-z0-9_])(?:xoxe\.)?(?:xox[abposr]-|xapp-)[A-Za-z0-9-]{16,}"#,
                     source: .secretSensitiveField, requiredLiterals: ["xoxa-", "xoxb-", "xoxp-", "xoxo-", "xoxs-", "xoxr-", "xapp-"]),
        ValuePattern(pattern: #"(?<![A-Za-z0-9_])AIza[A-Za-z0-9_-]{35}(?![A-Za-z0-9_-])"#,
                     source: .secretSensitiveField, requiredLiterals: ["AIza"]),
        ValuePattern(pattern: #"(?<![A-Za-z0-9_])glpat-[A-Za-z0-9_-]{16,}"#,
                     source: .secretSensitiveField, requiredLiterals: ["glpat-"]),
        ValuePattern(pattern: #"(?<![A-Za-z0-9_])npm_[A-Za-z0-9]{36}(?![A-Za-z0-9])"#,
                     source: .secretSensitiveField, requiredLiterals: ["npm_"]),
        ValuePattern(pattern: #"(?<![A-Za-z0-9_])pypi-AgE[A-Za-z0-9_-]{20,}"#,
                     source: .secretSensitiveField, requiredLiterals: ["pypi-AgE"]),
        ValuePattern(pattern: #"(?<![A-Za-z0-9_])SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}(?![A-Za-z0-9_-])"#,
                     source: .secretSensitiveField, requiredLiterals: ["SG."]),
        ValuePattern(pattern: #"-----BEGIN PGP PRIVATE KEY BLOCK-----[\s\S]*?(?:-----END PGP PRIVATE KEY BLOCK-----|\z)"#,
                     source: .secretSensitiveField, requiredLiterals: ["-----BEGIN PGP PRIVATE KEY BLOCK-----"]),
        ValuePattern(pattern: #"(?m)^PuTTY-User-Key-File-[23]:[^\r\n]*[\s\S]*?(?:^Private-MAC:[^\r\n]*|\z)"#,
                     source: .secretSensitiveField, requiredLiterals: ["PuTTY-User-Key-File-"]),
        ValuePattern(pattern: #"(?<![A-Za-z0-9+/])LS0tLS1CRUdJTi[A-Za-z0-9+/=]{20,}"#,
                     source: .secretSensitiveField, requiredLiterals: ["LS0tLS1CRUdJTi"], validation: .encodedPrivateKey),
        // Wire keys may use mixed case, so a case-sensitive literal gate would be incomplete.
        ValuePattern(pattern: #"(?i)\b(?:AccountKey|SharedAccessKey|SharedAccessSignature)[\t ]*=[\t ]*([^;\s\"'<>()\[\]{},]+)"#,
                     source: .secretSensitiveField, requiredLiterals: [], concealedGroup: 1)
    ]


    private static func scan(in text: String, context: RequestContext, visibleURLContextOnly: Bool = false,
                             visit: (Match, Bool) -> Bool) throws {
        try context.checkpoint()
        var contiguousText = text
        contiguousText.makeContiguousUTF8()
        let nsText = contiguousText as NSString
        var keepGoing = true
        for value in valuePatterns {
            if !keepGoing { break }
            try context.checkpoint()
            guard let regex = value.regex else { throw PreviewFailure.malformedDocument }
            if visibleURLContextOnly, !value.preservesVisibleURLContext { continue }
            if !value.requiredLiterals.isEmpty, !mayContain(anyOf: value.requiredLiterals, in: contiguousText) { continue }
            var failure: (any Error)?
            var progressEvents = 0
            regex.enumerateMatches(in: contiguousText, options: [.reportProgress],
                                   range: NSRange(location: 0, length: nsText.length)) { match, _, stop in
                if match == nil {
                    progressEvents &+= 1
                    if progressEvents & progressCheckpointMask != 0 { return }
                }
                do { try context.checkpoint() }
                catch { failure = error; stop.pointee = true; return }
                guard let match, accepts(match, for: value.validation, in: nsText) else { return }
                let range = match.range(at: value.concealedGroup)
                guard range.location != NSNotFound, range.length > 0 else { return }
                keepGoing = visit(Match(utf16Range: range.location..<NSMaxRange(range), kind: value.source), value.preservesVisibleURLContext)
                if !keepGoing { stop.pointee = true }
            }
            if let failure { throw failure }
        }
        try context.checkpoint()
    }

    /// ASCII spellings occupy the same bytes in valid UTF-8, so absence from the bytes proves
    /// absence from the text. Strings without contiguous storage conservatively report a possible match.
    private static func mayContain(anyOf literals: [String], in text: String) -> Bool {
        let found = text.utf8.withContiguousStorageIfAvailable { haystack -> Bool in
            guard let base = haystack.baseAddress, !haystack.isEmpty else { return false }
            return literals.contains { literal in
                var literal = literal
                return literal.withUTF8 { needle in
                    memmem(base, haystack.count, needle.baseAddress, needle.count) != nil
                }
            }
        }
        return found ?? true
    }

    private static func accepts(_ match: NSTextCheckingResult, for validation: ValueValidation,
                                in text: NSString) -> Bool {
        switch validation {
        case .unconditional: return true
        case .basicAuthorization:
            let token = match.range(at: 1)
            // A pathological credential is concealed without decoding a huge value. For normal
            // Basic values, validate the colon that separates user and password after decoding.
            if token.length > 4_096 { return true }
            guard let decoded = Data(base64Encoded: text.substring(with: token)) else { return false }
            return decoded.contains(58) && decoded.allSatisfy { $0 >= 32 && $0 != 127 }
        case .bearerAuthorization:
            let token = match.range(at: 1)
            if token.length >= 16 { return true }
            let tokenPrefix = text.substring(with: token)
            return tokenPrefix.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) || "_+/=.-".unicodeScalars.contains($0) }
        case .encodedPrivateKey:
            let token = match.range
            // Decode only the first complete base64 quartet prefix, enough for a PEM header.
            // Public keys and certificates share the encoded BEGIN prefix but are not secrets.
            let length = min(256, token.length)
            let tokenPrefix = text.substring(with: NSRange(location: token.location, length: length - length % 4))
            guard let decoded = Data(base64Encoded: tokenPrefix), let header = String(data: decoded, encoding: .utf8) else { return false }
            guard let firstLine = header.split(whereSeparator: { $0.isNewline }).first else { return false }
            return firstLine.hasPrefix("-----BEGIN ") && firstLine.contains("PRIVATE KEY") && firstLine.hasSuffix("-----")
        }
    }

}
