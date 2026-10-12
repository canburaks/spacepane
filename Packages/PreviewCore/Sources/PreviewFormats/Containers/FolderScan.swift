import Foundation
import Darwin
import PreviewContracts

/// Bounded, cancellable, descriptor-relative enumeration behind the folder summary.
///
/// - Every directory is opened component by component with `openat(…, O_DIRECTORY | O_NOFOLLOW)` from
///   one authorized root descriptor, so a link swapped in after the metadata read is refused rather than
///   followed. No path-based filesystem call is made below the root.
/// - Levels are listed breadth first, so the top level is always complete before a deeper level can use
///   up the budget. Within a folder entries are sorted before they are admitted.
/// - Package directories (`.app`, `.framework`, …) are listed as opaque `package` items and never entered.
///   A directory on another filesystem is listed but not entered, since a mount point can be a network
///   volume whose enumeration would block.
/// - Directories exactly at the depth limit are only *counted* (names, no metadata), so every folder
///   shows an item count even though its children are not listed.
/// - Anything that limits what is reported (entry/line/byte budgets, the shared name-read cap, an
///   unreadable folder, a skipped mount point) sets `isPartial`; counts that cannot be exact are omitted
///   rather than approximated.
///
/// The scan only reads names and `fstatat` metadata. It never opens, reads or follows any file.
struct FolderScan {
    /// One listed entry and the indexes of its listed children in `nodes`.
    struct Node {
        var entry: ContainerEntry
        var children: [Int] = []
    }

    private enum Kind: String {
        case file, directory, symlink, special, package
    }

    private struct Child {
        let name: String
        let info: stat
    }

    private struct DirectoryRead {
        var children: [Child] = []
        /// Visible names read, including those whose metadata could not be read.
        var visibleNames = 0
        var isComplete = true
    }

    private struct Pending {
        let node: Int?
        let components: [String]
    }

    /// Names read in every directory, listed or only counted. Bounds the total directory work.
    static let maximumScannedNames = 100_000

    private(set) var nodes: [Node] = []
    private(set) var rootChildren: [Int] = []
    private(set) var hiddenEntries = 0
    private(set) var inaccessibleEntries = 0
    private(set) var isPartial = false
    let depth: Int

    private let access: DirectoryReadAccess
    private let context: RequestContext
    private let includesHidden: Bool
    private let rootDescriptor: Int32
    private let rootDevice: dev_t
    private let maximumNamesPerDirectory: Int
    private let maximumNameBytes: Int
    private var budget: ListingBudget
    private var packages = FolderPackageClassifier()
    private var scannedNames = 0
    private var nameBytes = 0
    private var isFull = false

    /// `rootDescriptor` stays owned by the caller and must outlive the scan.
    init(rootDescriptor: Int32, rootDevice: dev_t, context: RequestContext, access: DirectoryReadAccess) {
        self.access = access
        let limits = ContainerLimits(context: context)
        self.context = context
        self.rootDescriptor = rootDescriptor
        self.rootDevice = rootDevice
        depth = min(max(context.options.folderDepth, PreviewRequestOptions.folderDepthRange.lowerBound),
                    PreviewRequestOptions.folderDepthRange.upperBound)
        includesHidden = context.options.includesHiddenItems
        maximumNamesPerDirectory = limits.maxEntries
        maximumNameBytes = limits.maxMetadataBytes
        budget = ListingBudget(context: context)
    }

    mutating func run() throws {
        var frontier = [Pending(node: nil, components: [])]
        for level in 1...depth {
            var next: [Pending] = []
            for pending in frontier {
                try context.checkpoint()
                if isFull { break }
                try expand(pending, level: level, next: &next)
            }
            frontier = next
            if frontier.isEmpty { break }
        }
    }

    /// Entries in hierarchical pre-order: a folder, then everything listed inside it.
    func orderedEntries() -> [ContainerEntry] {
        var result: [ContainerEntry] = []
        result.reserveCapacity(nodes.count)
        var stack = Array(rootChildren.reversed())
        while let index = stack.popLast() {
            result.append(nodes[index].entry)
            stack.append(contentsOf: nodes[index].children.reversed())
        }
        return result
    }

    // MARK: Enumeration

    private mutating func expand(_ pending: Pending, level: Int, next: inout [Pending]) throws {
        let descriptor: Int32
        do { descriptor = try openDirectory(pending.components) }
        catch {
            if pending.node == nil { throw error }
            try noteUnreadable(pending.node)
            return
        }
        let opened = access.stream(descriptor, root: pending.node == nil)
        guard let directory = opened.value else {
            access.close(descriptor)
            if pending.node == nil { throw access.mappedFailure(opened.error, fallback: .unreadableFile) }
            try noteUnreadable(pending.node)
            return
        }
        defer { access.closeStream(directory) }
        var read: DirectoryRead
        do { read = try readEntries(of: directory, descriptor: descriptor, root: pending.node == nil) }
        catch {
            if pending.node == nil { throw error }
            guard let failure = error as? PreviewFailure,
                  [.unavailableContent, .unreadableFile, .notRegularFile].contains(failure) else { throw error }
            try noteUnreadable(pending.node)
            return
        }
        read.children.sort(by: Self.nameOrder)
        // The count is exact only when every name was read; hidden names are not part of it.
        if read.isComplete, let parent = pending.node { nodes[parent].entry.itemCount = read.visibleNames }
        let prefix = pending.components.isEmpty ? "" : pending.components.joined(separator: "/") + "/"
        for child in read.children {
            try context.checkpoint()
            let kind = classify(child)
            nameBytes += child.name.utf8.count
            if nameBytes > maximumNameBytes { markFull(); break }
            let entry = ContainerEntry(path: prefix + child.name, kind: kind.rawValue,
                                       size: kind == .file ? max(0, Int(child.info.st_size)) : nil,
                                       modified: Self.date(child.info.st_mtimespec))
            // Directories may gain an item count, so they are priced as if they already had one.
            var priced = entry
            if kind == .directory { priced.itemCount = 0 }
            guard ListingBudget.fitsLine(priced, context: context) else { isPartial = true; continue }
            guard budget.admit(priced) else { markFull(); break }
            let index = nodes.count
            nodes.append(Node(entry: entry))
            if let parent = pending.node { nodes[parent].children.append(index) } else { rootChildren.append(index) }
            guard kind == .directory else { continue }
            if access.isDataless(child.info) {
                // Metadata may be listed, but missing directory contents are never counted or entered.
                isPartial = true
            } else if child.info.st_dev != rootDevice {
                // Never enter another filesystem; the folder is listed without a count.
                isPartial = true
            } else if level < depth {
                next.append(Pending(node: index, components: pending.components + [child.name]))
            } else {
                nodes[index].entry.itemCount = try countItems(inDirectoryNamed: child.name, in: descriptor)
            }
        }
    }

    private mutating func readEntries(of directory: UnsafeMutablePointer<DIR>, descriptor: Int32, root: Bool) throws -> DirectoryRead {
        var result = DirectoryRead()
        while true {
            _ = try access.metadata(descriptor: descriptor, at: .beforeEnumeration, fallback: .unreadableFile)
            let call = access.nextEntry(directory, root: root)
            guard let entry = call.value else {
                if call.error != 0 {
                    let failure = access.mappedFailure(call.error, fallback: .unreadableFile)
                    if failure == .unavailableContent { throw failure }
                    result.isComplete = false; isPartial = true
                } else {
                    _ = try access.metadata(descriptor: descriptor, at: .afterEnumeration, fallback: .unreadableFile)
                }
                break
            }
            scannedNames += 1
            if scannedNames.isMultiple(of: 256) { try context.checkpoint() }
            guard scannedNames <= Self.maximumScannedNames else { result.isComplete = false; isPartial = true; break }
            let shape = Self.nameShape(of: entry)
            if shape.isSelfOrParent { continue }
            if shape.isHidden && !includesHidden { hiddenEntries += 1; continue }
            guard result.visibleNames < maximumNamesPerDirectory else { result.isComplete = false; isPartial = true; break }
            result.visibleNames += 1
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            // fd-relative metadata keeps the original directory identity and never follows links.
            guard let info = try? access.childMetadata(parent: descriptor, name: name, at: .listedChild) else {
                inaccessibleEntries += 1
                isPartial = true
                continue
            }
            result.children.append(Child(name: name, info: info))
        }
        return result
    }

    /// Visible names directly inside the named child of `parentDescriptor`, or nil when the exact number
    /// is unavailable. Names are counted without being decoded or measured.
    private mutating func countItems(inDirectoryNamed name: String, in parentDescriptor: Int32) throws -> Int? {
        guard let descriptor = try? access.openDirectory(parent: parentDescriptor, name: name, root: false) else {
            inaccessibleEntries += 1; isPartial = true; return nil
        }
        let opened = access.stream(descriptor, root: false)
        guard let directory = opened.value else {
            access.close(descriptor)
            inaccessibleEntries += 1
            isPartial = true
            return nil
        }
        defer { access.closeStream(directory) }
        var count = 0
        while true {
            guard (try? access.metadata(descriptor: descriptor, at: .beforeEnumeration, fallback: .unreadableFile)) != nil else {
                isPartial = true; return nil
            }
            let call = access.nextEntry(directory, root: false)
            guard let entry = call.value else {
                if call.error != 0 { isPartial = true; return nil }
                guard (try? access.metadata(descriptor: descriptor, at: .afterEnumeration, fallback: .unreadableFile)) != nil else {
                    isPartial = true; return nil
                }
                return count
            }
            scannedNames += 1
            if scannedNames.isMultiple(of: 256) { try context.checkpoint() }
            guard scannedNames <= Self.maximumScannedNames else { isPartial = true; return nil }
            let shape = Self.nameShape(of: entry)
            if shape.isSelfOrParent || (shape.isHidden && !includesHidden) { continue }
            count += 1
        }
    }

    /// Opens a listed directory again from the root, one `O_NOFOLLOW` component at a time.
    private func openDirectory(_ components: [String]) throws -> Int32 {
        var current = try access.openDirectory(parent: rootDescriptor, name: ".", root: true)
        for component in components {
            let next: Int32
            do { next = try access.openDirectory(parent: current, name: component, root: false) }
            catch { access.close(current); throw error }
            access.close(current)
            current = next
        }
        return current
    }

    private mutating func noteUnreadable(_ node: Int?) throws {
        // The root was authorized and opened by the adapter; failing to enumerate it is a request failure.
        if node == nil { throw PreviewFailure.unreadableFile }
        inaccessibleEntries += 1
        isPartial = true
    }

    private mutating func markFull() {
        isFull = true
        isPartial = true
    }

    // MARK: Classification

    private mutating func classify(_ child: Child) -> Kind {
        switch child.info.st_mode & S_IFMT {
        case S_IFLNK: .symlink
        case S_IFDIR: packages.isPackage(name: child.name) ? .package : .directory
        case S_IFREG: .file
        default: .special
        }
    }

    private static func nameShape(of entry: UnsafeMutablePointer<dirent>) -> (isSelfOrParent: Bool, isHidden: Bool) {
        let length = Int(entry.pointee.d_namlen)
        return withUnsafePointer(to: &entry.pointee.d_name) {
            $0.withMemoryRebound(to: UInt8.self, capacity: max(length, 1)) { bytes in
                guard length > 0, bytes[0] == UInt8(ascii: ".") else { return (false, false) }
                let isSelf = length == 1 || (length == 2 && bytes[1] == UInt8(ascii: "."))
                return (isSelf, true)
            }
        }
    }

    private static func nameOrder(_ lhs: Child, _ rhs: Child) -> Bool {
        let result = lhs.name.localizedStandardCompare(rhs.name)
        return result == .orderedSame ? lhs.name < rhs.name : result == .orderedAscending
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }
}
