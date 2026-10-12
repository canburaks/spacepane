import Foundation
import Darwin
import PreviewContracts

/// Lists a folder from metadata only, up to the chosen depth. See `FolderScan` for the traversal
/// guarantees; this adapter opens the authorized directory and turns the scan into the shared listing
/// summary. It has no capability to read the content of any child.
public struct FolderSummaryAdapter: URLFormatAdapter {
    /// Files shown in the summary's largest-files ranking.
    private static let largestFileCount = 5

    private let access: DirectoryReadAccess

    public init() { access = DirectoryReadAccess() }
    init(access: DirectoryReadAccess) { self.access = access }

    public func parse(url: URL, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        guard url.isFileURL else { throw PreviewFailure.unreadableFile }
        return try access.policy.withoutMaterializing {
            try access.preflightRoot(url: url)
            return try parseMaterialized(url: url, context: context)
        }
    }

    private func parseMaterialized(url: URL, context: RequestContext) throws -> ParsedTextDocument {
        let descriptor = try access.openRoot(url: url)
        defer { access.close(descriptor) }
        let rootInfo = try access.metadata(descriptor: descriptor, at: .rootOpened)
        var scan = FolderScan(rootDescriptor: descriptor, rootDevice: rootInfo.st_dev, context: context, access: access)
        try scan.run()
        _ = try access.metadata(descriptor: descriptor, at: .rootFinal)
        let entries = scan.orderedEntries()
        let files = entries.filter { $0.kind == "file" }
        // Directory allocation sizes are intentionally never presented as recursive content sizes: the
        // total covers only the files listed above, and `partial`/`recursive` say how complete that is.
        let listedBytes = files.reduce(0) { total, file in
            let (sum, overflow) = total.addingReportingOverflow(file.size ?? 0)
            return overflow ? Int.max : sum
        }
        var extra: [(String, SummaryValue)] = [
            ("scope", .string(scan.depth == 1 ? "immediateChildren" : "nestedFolders")),
            ("inaccessibleEntries", .integer(scan.inaccessibleEntries)), ("recursive", .boolean(false)),
            ("depth", .integer(scan.depth)), ("hiddenEntries", .integer(scan.hiddenEntries)),
            ("fileCount", .integer(files.count)),
            ("folderCount", .integer(entries.reduce(0) { $0 + ($1.kind == "directory" ? 1 : 0) })),
            ("listedBytes", .integer(listedBytes))
        ]
        let largest = Self.largest(files)
        if largest.count > 1 {
            extra.append(("largestItems", .array(largest.map { .object([("path", .string($0.path)), ("bytes", $0.size.map { .integer($0) } ?? .null)]) })))
        }
        return try listingDocument(format: "directory", entries: entries, context: context, partial: scan.isPartial,
                                   extra: extra, assessNameRisks: true)
    }

    /// The biggest listed files, largest first; equal sizes keep their listing order.
    private static func largest(_ files: [ContainerEntry]) -> [ContainerEntry] {
        let ranked = files.enumerated().filter { ($0.element.size ?? 0) > 0 }.sorted {
            let (left, right) = ($0.element.size ?? 0, $1.element.size ?? 0)
            return left == right ? $0.offset < $1.offset : left > right
        }
        return ranked.prefix(largestFileCount).map(\.element)
    }
}
