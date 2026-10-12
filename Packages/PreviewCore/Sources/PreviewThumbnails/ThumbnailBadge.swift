import Foundation
import PreviewContracts

/// The short type label macOS draws on an icon thumbnail (`QLThumbnailReply.extensionBadge`; decision 027, Q-120).
///
/// The token is a catalog suffix, uppercased. It is a technical identifier, so it is never translated, and it
/// never comes from the file's name beyond its final extension: a file called `json.txt` is badged `TXT`, and
/// `report.final.json` is badged `JSON`, whatever the stem says. A file matched by its whole name (`Dockerfile`,
/// `package.json`, `.env`) or by no catalog suffix has no badge, because its name says nothing a suffix could.
public struct ThumbnailBadge: Equatable, Sendable {
    /// Longest token drawn. A longer suffix (`provisionprofile`) is left without a badge rather than cut short.
    public static let maximumLength = 8

    /// The suffix in capitals, one to eight ASCII letters, digits, `+` or `-`.
    public let token: String

    public init?(token: String) {
        guard (1...Self.maximumLength).contains(token.utf8.count), token.utf8.allSatisfy(Self.isAllowed) else { return nil }
        self.token = token.uppercased()
    }

    private static func isAllowed(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
            || byte == 0x2B || byte == 0x2D
    }

    /// The badge for the catalog format `url` is classified as, when the classification came from the file's
    /// suffix. The decision reads the name only; no file is opened.
    public static func matching(url: URL, catalog: FormatCatalog) -> ThumbnailBadge? {
        guard let format = catalog.classify(url: url), let descriptor = catalog.descriptor(for: format) else { return nil }
        let name = url.lastPathComponent.lowercased()
        // The whole name picked the format, so no suffix did.
        if descriptor.filenameAliases.contains(name) || descriptor.filenamePrefixes.contains(where: { name.hasPrefix($0) }) {
            return nil
        }
        let suffix = url.pathExtension.lowercased()
        guard !suffix.isEmpty, descriptor.suffixAliases.contains(suffix) else { return nil }
        return ThumbnailBadge(token: suffix)
    }
}

/// One request's outcome together with the badge every reply to it carries, whatever the outcome: the content
/// page, the glyph for a policy decision, the glyph for a timeout.
public struct ThumbnailResult: Sendable {
    public let outcome: ThumbnailOutcome
    public let badge: ThumbnailBadge?

    public init(outcome: ThumbnailOutcome, badge: ThumbnailBadge?) {
        self.outcome = outcome
        self.badge = badge
    }
}
