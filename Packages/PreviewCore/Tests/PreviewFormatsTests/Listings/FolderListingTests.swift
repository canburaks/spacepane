import Foundation
import Darwin
import Testing
import PreviewContracts
@testable import PreviewFormats

/// Folder summaries: depth, hidden items, packages, links, unreadable folders, totals and limits.
@Suite("Folder listing")
struct FolderListingTests {
    private struct Listing {
        let root: [String: Any]
        let entries: [[String: Any]]
        var paths: [String] { entries.compactMap { $0["path"] as? String } }
        func entry(_ path: String) -> [String: Any]? { entries.first { $0["path"] as? String == path } }
        func number(_ key: String) -> Int? { root[key] as? Int }
    }

    /// root/
    ///   a.txt (5 B), b-10.txt (7 B), b-2.txt (3 B), .hidden-file, .hidden-dir/inner.txt
    ///   docs/ readme.md (11 B), guide/ (deep.md (13 B), inner/ (deepest.txt (17 B)))
    ///   Fake.app/Contents/secret.txt, link -> docs
    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        func write(_ path: String, _ count: Int) throws {
            let url = root.appendingPathComponent(path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0x78, count: count).write(to: url)
        }
        try write("a.txt", 5)
        try write("b-10.txt", 7)
        try write("b-2.txt", 3)
        try write(".hidden-file", 2)
        try write(".hidden-dir/inner.txt", 2)
        try write("docs/readme.md", 11)
        try write("docs/guide/deep.md", 13)
        try write("docs/guide/inner/deepest.txt", 17)
        try write("Fake.app/Contents/secret.txt", 19)
        try fileManager.createSymbolicLink(atPath: root.appendingPathComponent("link").path, withDestinationPath: "docs")
        return root
    }

    private func list(_ url: URL, depth: Int = 1, hidden: Bool = false, budget: PreviewBudget = PreviewBudget(maxMilliseconds: 30_000)) throws -> Listing {
        var context = RequestContext(budget: budget)
        context.options = PreviewRequestOptions(folderDepth: depth, includesHiddenItems: hidden)
        let document = try FolderSummaryAdapter().parse(url: url, context: context)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(document.text.utf8)) as? [String: Any])
        return Listing(root: object, entries: object["entries"] as? [[String: Any]] ?? [])
    }

    @Test func depthOneListsOnlyVisibleImmediateChildrenInNaturalOrder() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let listing = try list(root)
        #expect(listing.paths == ["a.txt", "b-2.txt", "b-10.txt", "docs", "Fake.app", "link"])
        #expect(listing.number("depth") == 1)
        #expect(listing.root["scope"] as? String == "immediateChildren")
        #expect(listing.root["recursive"] as? Bool == false)
        #expect(listing.root["partial"] as? Bool == false)
        #expect(listing.number("hiddenEntries") == 2)
        #expect(listing.number("inaccessibleEntries") == 0)
        #expect(listing.number("listedEntries") == 6)
    }

    @Test func kindsSizesDatesAndPerFolderItemCountsAreReported() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let listing = try list(root)
        #expect(listing.entry("a.txt")?["type"] as? String == "file")
        #expect(listing.entry("a.txt")?["bytes"] as? Int == 5)
        #expect(listing.entry("docs")?["type"] as? String == "directory")
        #expect(listing.entry("docs")?["bytes"] is NSNull)
        // docs holds readme.md and guide (hidden names are not counted).
        #expect(listing.entry("docs")?["items"] as? Int == 2)
        #expect(listing.entry("link")?["type"] as? String == "symlink")
        #expect(listing.entry("link")?["items"] == nil)
        for entry in listing.entries { #expect(entry["modified"] is String) }
        let stamp = try #require(listing.entry("a.txt")?["modified"] as? String)
        let modified = try #require(ISO8601DateFormatter().date(from: stamp))
        #expect(abs(modified.timeIntervalSinceNow) < 120)
    }

    @Test func totalsCoverOnlyTheListedFilesAndSayTheyAreNotRecursive() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let one = try list(root)
        #expect(one.number("fileCount") == 3)
        #expect(one.number("folderCount") == 1)
        #expect(one.number("listedBytes") == 15)
        let nested = try list(root, depth: 4)
        #expect(nested.number("fileCount") == 3 + 3)
        #expect(nested.number("listedBytes") == 15 + 11 + 13 + 17)
        #expect(nested.root["recursive"] as? Bool == false)
        #expect(nested.root["scope"] as? String == "nestedFolders")
    }

    @Test func hiddenItemsAreListedOnlyWhenRequestedAndAreCountedOtherwise() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let shown = try list(root, hidden: true)
        #expect(shown.paths.contains(".hidden-file"))
        #expect(shown.paths.contains(".hidden-dir"))
        #expect(shown.number("hiddenEntries") == 0)
        #expect(shown.entry(".hidden-dir")?["items"] as? Int == 1)
        let hiddenOff = try list(root, depth: 2)
        #expect(!hiddenOff.paths.contains { $0.contains(".hidden") })
        #expect(hiddenOff.number("hiddenEntries") == 2)
    }

    @Test func depthTwoThroughFourListNestedFoldersAndCountTheBoundary() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let two = try list(root, depth: 2)
        #expect(two.paths.contains("docs/readme.md"))
        #expect(two.paths.contains("docs/guide"))
        #expect(!two.paths.contains("docs/guide/deep.md"))
        // guide sits at the depth limit: its children are counted, not listed.
        #expect(two.entry("docs/guide")?["items"] as? Int == 2)
        let three = try list(root, depth: 3)
        #expect(three.paths.contains("docs/guide/deep.md"))
        #expect(three.paths.contains("docs/guide/inner"))
        #expect(!three.paths.contains("docs/guide/inner/deepest.txt"))
        #expect(three.entry("docs/guide/inner")?["items"] as? Int == 1)
        let four = try list(root, depth: 4)
        #expect(four.paths.contains("docs/guide/inner/deepest.txt"))
        #expect(four.number("depth") == 4)
    }

    @Test func nestedEntriesFollowTheirParentInHierarchicalOrder() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try list(root, depth: 3).paths
        let docs = try #require(paths.firstIndex(of: "docs"))
        #expect(Array(paths[docs...(docs + 4)]) == ["docs", "docs/guide", "docs/guide/deep.md", "docs/guide/inner", "docs/readme.md"])
    }

    @Test func packagesAreOpaqueItemsAndTheirContentsAreNeverEntered() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for depth in [1, 4] {
            let listing = try list(root, depth: depth)
            let package = try #require(listing.entry("Fake.app"))
            #expect(package["type"] as? String == "package")
            #expect(package["items"] == nil)
            #expect(package["bytes"] is NSNull)
            #expect(!listing.paths.contains { $0.hasPrefix("Fake.app/") })
        }
    }

    @Test func packageSuffixesAreMatchedByNameAndCaseInsensitively() {
        var classifier = FolderPackageClassifier()
        for name in ["Tool.app", "Lib.FRAMEWORK", "x.bundle", "p.plugin", "e.appex", "b.xcarchive", "Photos Library.photoslibrary", "x.tar.app"] {
            let isPackage = classifier.isPackage(name: name)
            #expect(isPackage, Comment(rawValue: name))
        }
        for name in ["plain", ".app", "archive.zip", "notes.txt", "Mix.app.bak", "a.", "dir.2024"] {
            let isPackage = classifier.isPackage(name: name)
            #expect(!isPackage, Comment(rawValue: name))
        }
    }

    @Test func symlinksAreListedButNeverFollowed() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("outside".utf8).write(to: outside.appendingPathComponent("outside-secret.txt"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("escape").path, withDestinationPath: outside.path)
        let listing = try list(root, depth: 4)
        #expect(listing.entry("escape")?["type"] as? String == "symlink")
        #expect(listing.entry("link")?["type"] as? String == "symlink")
        #expect(!listing.paths.contains { $0.hasPrefix("escape/") || $0.hasPrefix("link/") })
        #expect(!listing.paths.contains { $0.contains("outside-secret") })
    }

    @Test func aSymlinkAsTheRootIsRefusedInsteadOfFollowed() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("link")
        #expect(throws: PreviewFailure.unreadableFile) { try list(link) }
    }

    @Test func anUnreadableSubfolderIsCountedAsInaccessibleAndFlagsThePartialListing() throws {
        try #require(geteuid() != 0, "Permission checks do not apply to root")
        let root = try makeFixture()
        let locked = root.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        try Data("x".utf8).write(to: locked.appendingPathComponent("inner.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: root)
        }
        // At the depth limit the count fails; one level shallower the enumeration fails.
        for depth in [1, 2] {
            let listing = try list(root, depth: depth)
            #expect(listing.entry("locked")?["type"] as? String == "directory")
            #expect(listing.entry("locked")?["items"] == nil)
            #expect(listing.number("inaccessibleEntries") == 1)
            #expect(listing.root["partial"] as? Bool == true)
            #expect(listing.paths.contains("a.txt"))
        }
    }

    @Test func reachingTheEntryBudgetFlagsPartialAndKeepsEveryTopLevelEntryBeforeDeeperOnes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<30 {
            let folder = root.appendingPathComponent("folder-\(String(format: "%02d", index))", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            for child in 0..<10 { try Data("x".utf8).write(to: folder.appendingPathComponent("file-\(child).txt")) }
        }
        // 600 nodes leave room for roughly 40 entries after the summary's own fields.
        let listing = try list(root, depth: 2, budget: PreviewBudget(maxJSONNodes: 600, maxMilliseconds: 30_000))
        #expect(listing.root["partial"] as? Bool == true)
        let topLevel = listing.paths.filter { !$0.contains("/") }
        #expect(topLevel.count == 30)
        #expect(listing.paths.count < 330)
        #expect(listing.paths.count > 30)
        #expect(listing.number("listedEntries") == listing.paths.count)
        // Totals describe the listed files only, and the root says it is not a recursive total.
        let listedFiles = listing.entries.filter { $0["type"] as? String == "file" }.count
        #expect(listing.number("fileCount") == listedFiles)
        #expect(listing.number("listedBytes") == listedFiles)
        #expect(listing.root["recursive"] as? Bool == false)
    }

    @Test func aSingleFolderBeyondTheNodeBudgetListsItsFirstEntriesAndIsPartial() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<40 { try Data().write(to: root.appendingPathComponent("f\(index).txt")) }
        let listing = try list(root, budget: PreviewBudget(maxJSONNodes: 100, maxMilliseconds: 30_000))
        #expect(listing.root["partial"] as? Bool == true)
        #expect(listing.paths.count < 40)
    }

    @Test func theLargestFilesAreRankedAmongTheListedEntriesOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for (index, size) in [10, 50, 30, 70, 20, 60, 40].enumerated() {
            try Data(repeating: 0x78, count: size).write(to: root.appendingPathComponent("file-\(index).bin"))
        }
        let listing = try list(root)
        let ranking = try #require(listing.root["largestItems"] as? [[String: Any]])
        #expect(ranking.compactMap { $0["bytes"] as? Int } == [70, 60, 50, 40, 30])
        #expect(ranking.compactMap { $0["path"] as? String } == ["file-3.bin", "file-5.bin", "file-1.bin", "file-6.bin", "file-2.bin"])
        // One file has nothing to rank against.
        let single = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: single, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: single) }
        try Data("x".utf8).write(to: single.appendingPathComponent("only.txt"))
        #expect(try list(single).root["largestItems"] == nil)
    }

    @Test func listingNeverReadsOrChangesAnyChild() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        func snapshot() throws -> [String: Date] {
            var result: [String: Date] = [:]
            let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: []))
            for case let url as URL in enumerator {
                result[url.path] = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            }
            return result
        }
        let before = try snapshot()
        let contents = try Data(contentsOf: root.appendingPathComponent("docs/readme.md"))
        let listing = try list(root, depth: 4, hidden: true)
        #expect(!listing.entries.isEmpty)
        #expect(try snapshot() == before)
        #expect(try Data(contentsOf: root.appendingPathComponent("docs/readme.md")) == contents)
    }

    @Test func aMissingOrNonDirectoryRootFailsWithTypedErrors() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: PreviewFailure.missingFile) { try list(root.appendingPathComponent("absent")) }
        #expect(throws: PreviewFailure.unreadableFile) { try list(root.appendingPathComponent("a.txt")) }
        #expect(throws: PreviewFailure.unreadableFile) { try list(URL(string: "https://example.com/folder")!) }
    }

    @Test func aCancelledRequestStopsBeforeTouchingTheFolder() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let task = Task.detached { () -> Bool in
            while !Task.isCancelled { await Task.yield() }
            var context = RequestContext(budget: .standard)
            context.options = PreviewRequestOptions(folderDepth: 4)
            do { _ = try FolderSummaryAdapter().parse(url: root, context: context); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        task.cancel()
        #expect(await task.value)
    }

    @Test func requestDepthOutsideTheSupportedRangeIsClamped() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var context = RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000))
        context.options.folderDepth = 99
        let document = try FolderSummaryAdapter().parse(url: root, context: context)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(document.text.utf8)) as? [String: Any])
        #expect(object["depth"] as? Int == 4)
        context.options.folderDepth = -3
        let shallow = try FolderSummaryAdapter().parse(url: root, context: context)
        #expect(try #require(try JSONSerialization.jsonObject(with: Data(shallow.text.utf8)) as? [String: Any])["depth"] as? Int == 1)
    }
}
