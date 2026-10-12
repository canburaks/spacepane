import Foundation

/// Flat listing paths nested into folders, with each folder's item count and summed size.
///
/// Counts and sizes are *listed* facts, never filesystem totals. A folder shows an exact count only
/// when the adapter supplied one (`items`) or, for an archive, when every entry was listed; a folder
/// whose contents were only partly listed reports a lower bound, and a folder whose contents were not
/// listed at all reports no size. `isComplete` summarizes which case a number is in.
struct SafeListingTree: Equatable, Sendable {
    struct Node: Equatable, Sendable {
        let name: String
        /// Slash-separated path from the listing root, without a trailing slash.
        let path: String
        /// The adapter's `type` for a listed entry; "directory" for a folder, listed or implied.
        let kind: String
        let isFolder: Bool
        /// A file's own listed size.
        let bytes: Int64?
        let modified: Date?
        let isEncrypted: Bool
        /// Direct children: exact, or at least this many when `itemCountIsLowerBound`. Nil when unknown.
        let itemCount: Int?
        let itemCountIsLowerBound: Bool
        /// Folders only: the sum of listed file sizes inside. Nil when no content was listed.
        let listedBytes: Int64?
        let listedBytesIsLowerBound: Bool
        /// Folders first, then natural name order.
        let children: [Node]
        /// Indexes into `SafeListing.entries` of the entries that produced this node (none when implied).
        let entryIndexes: [Int]

        // Exact code units for the path, so canonically equivalent spellings stay distinct.
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.path.utf8.elementsEqual(rhs.path.utf8) && lhs.name.utf8.elementsEqual(rhs.name.utf8)
                && lhs.kind == rhs.kind && lhs.isFolder == rhs.isFolder && lhs.bytes == rhs.bytes
                && lhs.modified == rhs.modified && lhs.isEncrypted == rhs.isEncrypted
                && lhs.itemCount == rhs.itemCount && lhs.itemCountIsLowerBound == rhs.itemCountIsLowerBound
                && lhs.listedBytes == rhs.listedBytes && lhs.listedBytesIsLowerBound == rhs.listedBytesIsLowerBound
                && lhs.entryIndexes == rhs.entryIndexes && lhs.children == rhs.children
        }
    }

    /// Nodes (listed entries plus implied folders) above this make the tree unavailable; Files remains.
    static let maximumNodes = 60_000
    /// Path components above this make the tree unavailable.
    static let maximumComponents = 64

    let roots: [Node]
    let nodeCount: Int
    let isPartial: Bool
    let usesUTC: Bool
    /// `SafeListing.entries` indexes in tree order. Every entry appears exactly once.
    let entryOrder: [Int]

    /// Nil when the listing exceeds the node or depth bounds.
    static func build(_ listing: SafeListing) -> SafeListingTree? {
        var builder = Builder()
        for (index, entry) in listing.entries.enumerated() {
            guard builder.add(entry, at: index) else { return nil }
        }
        return builder.finish(isPartial: listing.isPartial, usesUTC: listing.usesUTC)
    }

    private struct Draft {
        let name: String
        let path: String
        var kind: String
        let isFolder: Bool
        var bytes: Int64?
        var modified: Date?
        var isEncrypted = false
        var explicitItems: Int?
        var entryIndexes: [Int] = []
        var children: [Int] = []
    }

    private struct Builder {
        struct FolderKey: Hashable {
            let parent: Int
            let name: String
        }
        var drafts: [Draft] = []
        var roots: [Int] = []
        var folders: [FolderKey: Int] = [:]
        var orphans: [Int] = []

        mutating func add(_ entry: SafeListingEntry, at index: Int) -> Bool {
            let components = entry.path.split(separator: "/", omittingEmptySubsequences: true)
            guard components.count <= SafeListingTree.maximumComponents else { return false }
            guard let last = components.last else { orphans.append(index); return true }
            var parent = -1
            var path = ""
            for component in components.dropLast() {
                path = path.isEmpty ? String(component) : path + "/" + component
                guard let folder = folder(named: String(component), path: path, under: parent) else { return false }
                parent = folder
            }
            path = path.isEmpty ? String(last) : path + "/" + last
            if entry.isDirectory {
                guard let folder = folder(named: String(last), path: path, under: parent) else { return false }
                drafts[folder].entryIndexes.append(index)
                if drafts[folder].modified == nil { drafts[folder].modified = entry.modified }
                if drafts[folder].explicitItems == nil { drafts[folder].explicitItems = entry.itemCount }
            } else {
                // A repeated file path stays a separate node: the listing shows what the archive holds.
                guard let leaf = node(named: String(last), path: path, kind: entry.kind, isFolder: false, under: parent) else { return false }
                drafts[leaf].bytes = entry.bytes
                drafts[leaf].modified = entry.modified
                drafts[leaf].isEncrypted = entry.isEncrypted
                drafts[leaf].entryIndexes = [index]
            }
            return true
        }

        private mutating func folder(named name: String, path: String, under parent: Int) -> Int? {
            let key = FolderKey(parent: parent, name: name)
            if let existing = folders[key] { return existing }
            guard let index = node(named: name, path: path, kind: "directory", isFolder: true, under: parent) else { return nil }
            folders[key] = index
            return index
        }

        private mutating func node(named name: String, path: String, kind: String, isFolder: Bool, under parent: Int) -> Int? {
            guard drafts.count < SafeListingTree.maximumNodes else { return nil }
            let index = drafts.count
            drafts.append(Draft(name: name, path: path, kind: kind, isFolder: isFolder))
            if parent < 0 { roots.append(index) } else { drafts[parent].children.append(index) }
            return index
        }

        func finish(isPartial: Bool, usesUTC: Bool) -> SafeListingTree {
            let sortedChildren = drafts.map { sorted($0.children) }
            let sortedRoots = sorted(roots)
            // A child is always created after its parent, so walking backwards finishes children first.
            var complete = [Bool](repeating: true, count: drafts.count)
            var built = [Node?](repeating: nil, count: drafts.count)
            for index in drafts.indices.reversed() {
                let draft = drafts[index]
                let children = sortedChildren[index].compactMap { built[$0] }
                var itemCount: Int?
                var itemCountIsLowerBound = false
                var listedBytes: Int64?
                if draft.isFolder {
                    let explicit = draft.explicitItems
                    let childrenComplete = sortedChildren[index].allSatisfy { complete[$0] }
                    complete[index] = childrenComplete && (explicit.map { $0 == children.count } ?? !isPartial)
                    itemCount = explicit ?? (children.isEmpty ? nil : children.count)
                    itemCountIsLowerBound = explicit == nil && !children.isEmpty && isPartial
                    if !children.isEmpty || explicit == 0 {
                        listedBytes = children.reduce(Int64(0)) { total, child in
                            let (sum, overflow) = total.addingReportingOverflow((child.isFolder ? child.listedBytes : child.bytes) ?? 0)
                            return overflow ? Int64.max : sum
                        }
                    }
                }
                built[index] = Node(
                    name: draft.name, path: draft.path, kind: draft.kind, isFolder: draft.isFolder, bytes: draft.bytes,
                    modified: draft.modified, isEncrypted: draft.isEncrypted, itemCount: itemCount,
                    itemCountIsLowerBound: itemCountIsLowerBound, listedBytes: listedBytes,
                    listedBytesIsLowerBound: draft.isFolder && listedBytes != nil && !complete[index],
                    children: children, entryIndexes: draft.entryIndexes)
            }
            var order: [Int] = []
            var stack = Array(sortedRoots.reversed())
            while let index = stack.popLast() {
                order.append(contentsOf: drafts[index].entryIndexes)
                stack.append(contentsOf: sortedChildren[index].reversed())
            }
            order.append(contentsOf: orphans)
            return SafeListingTree(roots: sortedRoots.compactMap { built[$0] }, nodeCount: drafts.count,
                                   isPartial: isPartial, usesUTC: usesUTC, entryOrder: order)
        }

        /// Folders first, then natural name order; equal names keep their creation order.
        private func sorted(_ ids: [Int]) -> [Int] {
            guard ids.count > 1 else { return ids }
            let compare = NaturalOrder.comparison(for: ids.map { drafts[$0].name })
            return ids.sorted { lhs, rhs in
                let (left, right) = (drafts[lhs], drafts[rhs])
                if left.isFolder != right.isFolder { return left.isFolder }
                let result = compare(left.name, right.name)
                return result == .orderedSame ? lhs < rhs : result == .orderedAscending
            }
        }
    }
}
