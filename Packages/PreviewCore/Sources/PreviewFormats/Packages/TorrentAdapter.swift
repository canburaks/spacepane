import Foundation
import CryptoKit
import PreviewContracts

/// Summarizes a BitTorrent metainfo file (`.torrent`): name, files, sizes, piece layout, creation facts,
/// the info-hashes and the tracker hosts.
///
/// Nothing is contacted: no tracker, web seed or DHT node is queried and no piece is verified.
/// Announce URLs are reduced to scheme, host and port because their paths and queries commonly carry a
/// private per-user passkey; free-text fields that look like they carry such a key or a credentialed
/// URL are concealed.
public struct TorrentAdapter: BinaryFormatAdapter {
    static let maximumTrackers = 32
    private static let pieceHashLength = 20

    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        var scanner = BencodeParser(bytes: [UInt8](input.data), context: context)
        let root = try scanner.parseDocument()
        let parser = scanner
        guard case .dictionary = root, let infoEntry = root.entry("info"), case .dictionary = infoEntry.value else {
            throw PreviewFailure.malformedDocument
        }
        let info = infoEntry.value
        let text = { (value: BencodeValue?) -> String? in
            guard case .string(let range)? = value else { return nil }
            let result = parser.text(range)
            return result.isEmpty ? nil : result
        }
        let integer = { (value: BencodeValue?) -> Int64? in
            guard case .integer(let number)? = value else { return nil }
            return number
        }
        let name = text(info.entry("name.utf-8")?.value) ?? text(info.entry("name")?.value)

        let files = try Self.files(info: info, name: name, parser: parser, context: context)
        guard !files.isEmpty else { throw PreviewFailure.malformedDocument }
        var total: Int64 = 0
        for file in files.items {
            let (sum, overflow) = total.addingReportingOverflow(file.length)
            guard !overflow else { throw PreviewFailure.malformedDocument }
            total = sum
        }

        var fields = SummaryFields()
        fields.text("name", name)
        fields.text("layout", files.layout.rawValue)
        fields.number("fileCount", files.count)
        fields.number("totalBytes", total)
        if let length = integer(info.entry("piece length")?.value), length > 0 { fields.number("pieceLength", length) }
        var hasV1Pieces = false
        if case .string(let range)? = info.entry("pieces")?.value {
            guard range.count % Self.pieceHashLength == 0 else { throw PreviewFailure.malformedDocument }
            fields.number("pieceCount", range.count / Self.pieceHashLength)
            hasV1Pieces = true
        }
        fields.flag("private", integer(info.entry("private")?.value).map { $0 == 1 })
        if let seconds = integer(root.entry("creation date")?.value), (0...253_402_300_799).contains(seconds) {
            fields.date("created", Date(timeIntervalSince1970: TimeInterval(seconds)))
        }
        let createdBy = text(root.entry("created by")?.value)
        fields.text("createdBy", createdBy, sensitive: createdBy.map(Self.looksCredentialed) ?? false)
        let comment = text(root.entry("comment.utf-8")?.value) ?? text(root.entry("comment")?.value)
        fields.text("comment", comment, sensitive: comment.map(Self.looksCredentialed) ?? false)

        // The info-hash is taken over the exact encoded bytes of the `info` value, never a re-encoding.
        let infoBytes = Data(parser.bytes[infoEntry.valueRange])
        if hasV1Pieces { fields.text("infoHash", Data(Insecure.SHA1.hash(data: infoBytes)).hexadecimal().lowercased()) }
        if integer(info.entry("meta version")?.value) == 2 {
            fields.text("infoHashV2", Data(SHA256.hash(data: infoBytes)).hexadecimal().lowercased())
        }
        fields.list("trackers", Self.trackerHosts(root: root, parser: parser), limit: Self.maximumTrackers)
        let webSeeds = Self.webSeedCount(root.entry("url-list")?.value)
        if webSeeds > 0 { fields.number("webSeeds", webSeeds) }

        let capacity = PackageSummary.listingCapacity(context)
        var entries: [ContainerEntry] = []
        var partial = false
        for file in files.items {
            try context.checkpoint()
            if entries.count == capacity { partial = true; break }
            guard (try? safeArchivePath(file.path)) != nil else { partial = true; continue }
            entries.append(ContainerEntry(path: file.path, kind: "file", size: Int(clamping: file.length)))
        }
        fields.listing(format: "BitTorrent", entries: entries, partial: partial)
        return try PackageSummary.document(fields.value, context: context)
    }

    // MARK: Files

    struct TorrentFile: Equatable {
        let path: String
        let length: Int64
    }

    struct FileSet {
        enum Layout: String { case singleFile, multipleFiles }
        let items: [TorrentFile]
        let layout: Layout
        var isEmpty: Bool { items.isEmpty }
        var count: Int { items.count }
    }

    /// Version 1 `length`/`files`, falling back to the version 2 `file tree`. Padding files (BEP 47) are not listed.
    private static func files(info: BencodeValue, name: String?, parser: BencodeParser, context: RequestContext) throws -> FileSet {
        let root = name ?? ""
        if case .list(let entries)? = info.entry("files")?.value {
            var items: [TorrentFile] = []
            for entry in entries {
                try context.checkpoint()
                guard case .dictionary = entry, case .integer(let length)? = entry.entry("length")?.value, length >= 0 else {
                    throw PreviewFailure.malformedDocument
                }
                if case .string(let range)? = entry.entry("attr")?.value, parser.text(range).contains("p") { continue }
                guard let components = pathComponents(entry.entry("path.utf-8")?.value ?? entry.entry("path")?.value, parser: parser) else {
                    throw PreviewFailure.malformedDocument
                }
                items.append(TorrentFile(path: ([root].filter { !$0.isEmpty } + components).joined(separator: "/"), length: length))
            }
            return FileSet(items: items, layout: .multipleFiles)
        }
        if case .integer(let length)? = info.entry("length")?.value, length >= 0 {
            return FileSet(items: [TorrentFile(path: root.isEmpty ? "?" : root, length: length)], layout: .singleFile)
        }
        if let tree = info.entry("file tree")?.value, case .dictionary = tree {
            var items: [TorrentFile] = []
            try walk(tree, prefix: [], depth: 0, into: &items, parser: parser, context: context)
            let single = items.count == 1 && !items[0].path.contains("/")
            let prefix = single || root.isEmpty ? "" : root + "/"
            return FileSet(items: items.map { TorrentFile(path: prefix + $0.path, length: $0.length) },
                           layout: single ? .singleFile : .multipleFiles)
        }
        throw PreviewFailure.malformedDocument
    }

    private static func pathComponents(_ value: BencodeValue?, parser: BencodeParser) -> [String]? {
        guard case .list(let parts)? = value, !parts.isEmpty else { return nil }
        var result: [String] = []
        for part in parts {
            guard case .string(let range) = part else { return nil }
            result.append(parser.text(range))
        }
        return result
    }

    private static func walk(_ node: BencodeValue, prefix: [String], depth: Int, into items: inout [TorrentFile],
                             parser: BencodeParser, context: RequestContext) throws {
        guard depth <= parser.maximumDepth else { throw PreviewFailure.structureTooDeep }
        guard case .dictionary(let entries) = node else { throw PreviewFailure.malformedDocument }
        for entry in entries {
            try context.checkpoint()
            if entry.key.isEmpty {
                guard case .integer(let length)? = entry.value.entry("length")?.value, length >= 0 else { throw PreviewFailure.malformedDocument }
                items.append(TorrentFile(path: prefix.joined(separator: "/"), length: length))
            } else {
                try walk(entry.value, prefix: prefix + [entry.key], depth: depth + 1, into: &items, parser: parser, context: context)
            }
        }
    }

    // MARK: Trackers and credential-like text

    /// Unique tracker origins in announce order: the main announce URL, then every tier of `announce-list`.
    private static func trackerHosts(root: BencodeValue, parser: BencodeParser) -> [String] {
        var urls: [String] = []
        if case .string(let range)? = root.entry("announce")?.value { urls.append(parser.text(range)) }
        if case .list(let tiers)? = root.entry("announce-list")?.value {
            for case .list(let tier) in tiers {
                for case .string(let range) in tier { urls.append(parser.text(range)) }
            }
        }
        var seen = Set<String>()
        return urls.compactMap(origin).filter { seen.insert($0).inserted }
    }

    /// `scheme://host[:port]` of a tracker URL; path, query and any user information are dropped.
    static func origin(_ url: String) -> String? {
        guard let components = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), ["http", "https", "udp", "ws", "wss"].contains(scheme),
              let host = components.host, !host.isEmpty else { return nil }
        // Foundation reports an IPv6 literal with its brackets; a bare literal gets them for display.
        let authority = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "\(scheme)://\(authority)" + (components.port.map { ":\($0)" } ?? "")
    }

    private static func webSeedCount(_ value: BencodeValue?) -> Int {
        switch value {
        case .string?: 1
        case .list(let items)?: items.count
        default: 0
        }
    }

    /// Free text that appears to carry a tracker passkey, an access key or a credentialed or query-bearing URL.
    static func looksCredentialed(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if ["passkey", "authkey", "torrent_pass", "rsskey", "apikey", "api_key", "token", "secret", "password"].contains(where: lowered.contains) { return true }
        return lowered.contains("://") && (lowered.contains("?") || lowered.contains("@"))
    }
}
