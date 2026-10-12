import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private let english = Locale(identifier: "en_US")

func listingPresentation(_ json: String, format: FormatID = .folder, redactions: Int = 0) -> TextPresentation {
    TextPresentation(formatID: format, text: json, lineCount: json.split(separator: "\n", omittingEmptySubsequences: false).count,
                     byteCount: json.utf8.count, encoding: .utf8, redactionCount: redactions, syntax: .json)
}

let archiveListingJSON = """
{"archiveFormat":"ZIP","listedEntries":5,"partial":false,"timeZone":"UTC","entries":[
 {"path":"src/","type":"directory","bytes":0},
 {"path":"src/main.swift","type":"file","bytes":1500,"modified":"2026-10-05T12:30:00Z"},
 {"path":"src/util/helpers.swift","type":"file","bytes":500},
 {"path":"README.md","type":"file","bytes":2048,"modified":"2026-10-04T08:00:00Z"},
 {"path":"empty/","type":"directory","bytes":0}]}
"""

private func parsedListing(_ json: String) throws -> SafeListing {
    let listing = SafeListing.parse(listingPresentation(json))
    return try #require(listing)
}

private func builtTree(_ json: String) throws -> SafeListingTree {
    let tree = SafeListingTree.build(try parsedListing(json))
    return try #require(tree)
}

@Suite("Listing models")
struct ListingModelTests {
    // MARK: Shape detection

    @Test func aListingIsRecognizedByItsShapeForEveryRegisteredSummaryFormat() throws {
        for format in [FormatID.folder, .zip, .tar, .gzip, .xip] {
            let listing = try #require(SafeListing.parse(listingPresentation(archiveListingJSON, format: format)))
            #expect(listing.entries.count == 5)
            #expect(listing.usesUTC)
            #expect(!listing.isPartial)
        }
    }

    @Test func entriesCarryKindSizeDateEncryptionAndItemCount() throws {
        let json = #"{"partial":true,"entries":[{"path":"a","type":"file","bytes":3,"modified":"2026-01-01T00:00:00Z","encrypted":true},{"path":"d","type":"directory","bytes":null,"items":4}]}"#
        let listing = try #require(SafeListing.parse(listingPresentation(json)))
        #expect(listing.isPartial)
        #expect(!listing.usesUTC)
        #expect(listing.entries[0].bytes == 3)
        #expect(listing.entries[0].isEncrypted)
        #expect(listing.entries[0].modified == Date(timeIntervalSince1970: 1_767_225_600))
        #expect(listing.entries[1].bytes == nil)
        #expect(listing.entries[1].itemCount == 4)
        #expect(listing.entries[1].isDirectory)
    }

    @Test func textThatIsNotAListingIsNeverGivenFilesOrTreeModes() {
        let listing = archiveListingJSON
        // A user's own JSON file may look like a listing; only formats with a registered summary schema count.
        for format in [FormatID.json, .packageJSON, .jupyterNotebook, .jsonLines, .sourceCode] {
            #expect(SafeListing.parse(listingPresentation(listing, format: format)) == nil)
        }
        let notJSON = TextPresentation(formatID: .folder, text: listing, lineCount: 1, byteCount: 1, encoding: .utf8,
                                       redactionCount: 0, syntax: .plain)
        #expect(SafeListing.parse(notJSON) == nil)
        let malformed = [
            #"{"archiveFormat":"directory","listedEntries":0}"#,
            #"{"entries":[]}"#,
            #"{"entries":"none"}"#,
            #"{"entries":[{"type":"file"}]}"#,
            #"{"entries":[{"path":"a"}]}"#,
            #"{"entries":[{"path":"","type":"file"}]}"#,
            #"{"entries":[{"path":"a","type":"file"},42]}"#,
            #"[{"path":"a","type":"file"}]"#,
            #"{"entries":[{"path":"a","type":"file","bytes":"#,
            #"{"entries":[{"path":"••••","type":"file","bytes":••••}]}"#
        ]
        for text in malformed { #expect(SafeListing.parse(listingPresentation(text)) == nil, Comment(rawValue: text)) }
    }

    @Test func fractionalOrBooleanSizesAreNotTreatedAsByteCounts() throws {
        let json = #"{"entries":[{"path":"a","type":"file","bytes":1.5},{"path":"b","type":"file","bytes":true},{"path":"c","type":"file","bytes":7}]}"#
        let listing = try #require(SafeListing.parse(listingPresentation(json)))
        #expect(listing.entries.map(\.bytes) == [nil, nil, 7])
    }

    @Test func anOversizedSummaryTextIsNotParsed() {
        let padding = String(repeating: "x", count: SafeListing.maximumSourceUTF8Bytes)
        let json = #"{"entries":[{"path":"\#(padding)","type":"file"}]}"#
        #expect(SafeListing.parse(listingPresentation(json)) == nil)
    }

    // MARK: Tree

    @Test func pathsNestIntoFoldersWithCountsAndSizesFoldersFirst() throws {
        let tree = try builtTree(archiveListingJSON)
        #expect(tree.roots.map(\.name) == ["empty", "src", "README.md"])
        let src = tree.roots[1]
        #expect(src.isFolder)
        #expect(src.children.map(\.name) == ["util", "main.swift"])
        #expect(src.itemCount == 2)
        #expect(src.listedBytes == 2_000)
        #expect(!src.listedBytesIsLowerBound)
        #expect(!src.itemCountIsLowerBound)
        let util = src.children[0]
        #expect(util.entryIndexes.isEmpty, "An implied folder has no entry of its own")
        #expect(util.itemCount == 1)
        #expect(util.listedBytes == 500)
        #expect(util.children[0].path == "src/util/helpers.swift")
        // An explicit directory entry with nothing inside reports no guess at its contents.
        #expect(tree.roots[0].itemCount == nil)
        #expect(tree.roots[0].listedBytes == nil)
        #expect(tree.nodeCount == 6)
        #expect(tree.entryOrder == [4, 0, 2, 1, 3])
        #expect(Set(tree.entryOrder) == Set(0..<5))
    }

    @Test func explicitDirectoryEntriesMergeWithImpliedParentsAndDuplicatesStaySeparate() throws {
        let json = #"""
        {"entries":[
         {"path":"a/b.txt","type":"file","bytes":1},
         {"path":"a/","type":"directory","bytes":0,"modified":"2026-01-01T00:00:00Z"},
         {"path":"a","type":"directory","bytes":0},
         {"path":"a/b.txt","type":"file","bytes":2},
         {"path":"x//y/./z.txt","type":"file","bytes":4},
         {"path":"/","type":"file","bytes":9}]}
        """#
        let listing = try #require(SafeListing.parse(listingPresentation(json)))
        let tree = try #require(SafeListingTree.build(listing))
        let a = try #require(tree.roots.first { $0.name == "a" })
        #expect(tree.roots.filter { $0.name == "a" }.count == 1)
        #expect(a.entryIndexes == [1, 2])
        #expect(a.modified == Date(timeIntervalSince1970: 1_767_225_600))
        #expect(a.children.map(\.name) == ["b.txt", "b.txt"])
        #expect(a.listedBytes == 3)
        let x = try #require(tree.roots.first { $0.name == "x" })
        #expect(x.children.first?.name == "y")
        #expect(x.children.first?.children.map(\.name) == ["."], "A dot component is an ordinary folder name")
        // The entry whose path has no component is kept, after the nested ones.
        #expect(tree.entryOrder.last == 5)
        #expect(Set(tree.entryOrder) == Set(0..<6))
    }

    @Test func aFileAndAFolderWithTheSameNameStaySeparateNodes() throws {
        let json = #"{"entries":[{"path":"same","type":"file","bytes":1},{"path":"same/inner.txt","type":"file","bytes":2}]}"#
        let tree = try builtTree(json)
        #expect(tree.roots.map { "\($0.name):\($0.isFolder)" } == ["same:true", "same:false"])
    }

    @Test func folderCountsFromTheAdapterAreExactAndUnlistedContentsGiveNoSize() throws {
        // `items` counted by the folder adapter: docs was entered (2 of 2 listed), deep is only counted.
        let json = #"""
        {"partial":false,"entries":[
         {"path":"docs","type":"directory","bytes":null,"items":2},
         {"path":"docs/a.txt","type":"file","bytes":10},
         {"path":"docs/deep","type":"directory","bytes":null,"items":5},
         {"path":"empty","type":"directory","bytes":null,"items":0}]}
        """#
        let tree = try builtTree(json)
        let docs = try #require(tree.roots.first { $0.name == "docs" })
        let deep = try #require(docs.children.first { $0.name == "deep" })
        #expect(deep.itemCount == 5)
        #expect(!deep.itemCountIsLowerBound)
        #expect(deep.listedBytes == nil, "Nothing inside was listed, so no size is shown")
        #expect(docs.itemCount == 2)
        #expect(docs.listedBytes == 10)
        // An unexpanded sibling folder makes the parent's size a lower bound, never a total.
        #expect(docs.listedBytesIsLowerBound)
        let empty = try #require(tree.roots.first { $0.name == "empty" })
        #expect(empty.itemCount == 0)
        #expect(empty.listedBytes == 0)
        #expect(!empty.listedBytesIsLowerBound)
    }

    @Test func aPartialArchiveListingMakesDerivedCountsAndSizesLowerBounds() throws {
        let json = #"{"partial":true,"entries":[{"path":"dir/a","type":"file","bytes":5},{"path":"dir/b","type":"file","bytes":6}]}"#
        let tree = try builtTree(json)
        let dir = tree.roots[0]
        #expect(dir.itemCount == 2)
        #expect(dir.itemCountIsLowerBound)
        #expect(dir.listedBytes == 11)
        #expect(dir.listedBytesIsLowerBound)
        #expect(tree.isPartial)
    }

    @Test func treesBeyondTheNodeOrDepthBoundsAreDeclinedWhileFilesStaysAvailable() throws {
        let deep = (0..<(SafeListingTree.maximumComponents + 1)).map { "d\($0)" }.joined(separator: "/")
        let json = #"{"entries":[{"path":"\#(deep)/f.txt","type":"file","bytes":1}]}"#
        let listing = try #require(SafeListing.parse(listingPresentation(json)))
        #expect(SafeListingTree.build(listing) == nil)
        let modes = SafePreviewModes(listingPresentation(json), locale: english)
        #expect(modes.tree == nil)
        #expect(modes.files != nil)
        #expect(modes.available.contains(.files))
        #expect(!modes.available.contains(.tree))
    }

    @Test func aLargeListingBuildsQuickly() throws {
        let entries = (0..<8_000).map { #"{"path":"dir\#($0 % 40)/sub\#($0 % 7)/file-\#($0).txt","type":"file","bytes":\#($0)}"# }
        let json = #"{"entries":["# + entries.joined(separator: ",") + "]}"
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            let modes = SafePreviewModes(listingPresentation(json), locale: english)
            #expect(modes.files?.rows.count == 8_000)
            #expect(modes.tree != nil)
        }
        #expect(elapsed < .seconds(5))
    }

    // MARK: Files table

    @Test func theFilesTableHasLocalizedColumnsInHierarchicalOrderWithFoldersFirst() throws {
        let listing = try #require(SafeListing.parse(listingPresentation(archiveListingJSON)))
        let tree = SafeListingTree.build(listing)
        let table = SafeListingFiles.table(listing, tree: tree, locale: english)
        #expect(table.columns == [PreviewStrings.text(.summaryName), PreviewStrings.text(.listingColumnKind),
                                  PreviewStrings.text(.listingColumnSize), PreviewStrings.text(.listingModifiedUTC)])
        #expect(table.rows.map { $0[0] } == ["empty/", "src/", "src/util/helpers.swift", "src/main.swift", "README.md"])
        #expect(table.rows.map { $0[1] } == [PreviewStrings.text(.summaryKindDirectory), PreviewStrings.text(.summaryKindDirectory),
                                             PreviewStrings.text(.summaryKindFile), PreviewStrings.text(.summaryKindFile),
                                             PreviewStrings.text(.summaryKindFile)])
        #expect(table.columnKinds == [.text, .text, .number, .date])
        // A directory shows no size even though a ZIP writes 0 bytes for it.
        #expect(table.rows[0][2] == "" && table.rows[1][2] == "")
        #expect(table.rows[4][2].lowercased().contains("kb"))
        #expect(table.sortKeys[2] == [nil, nil, 500, 1500, 2048])
        #expect(table.sortKeys[3]?[3] == Date(timeIntervalSince1970: 1_791_203_400).timeIntervalSince1970)
        #expect(table.rows[2][3] == "", "An entry without a date has an empty cell")
    }

    @Test func modifiedDatesShowTheStoredDigitsInUTCAndNeverShiftWithTheViewersTimeZone() throws {
        let listing = try #require(SafeListing.parse(listingPresentation(archiveListingJSON)))
        let table = SafeListingFiles.table(listing, tree: nil, locale: english)
        // Without a tree the adapter's listing order is kept.
        #expect(table.rows.map { $0[0] } == ["src/", "src/main.swift", "src/util/helpers.swift", "README.md", "empty/"])
        let text = table.rows[1][3]
        #expect(text.contains("12:30"))
        #expect(text.contains("2026"))
        let local = SafeListingFormatting.dateText(Date(timeIntervalSince1970: 1_791_203_400), locale: english, usesUTC: true)
        #expect(local == text)
    }

    @Test func numbersAndDatesFollowThePresentationLocaleWhileNamesStayVerbatim() throws {
        let json = #"{"entries":[{"path":"große Datei.txt","type":"file","bytes":1500000,"modified":"2026-10-05T12:30:00Z"}]}"#
        let listing = try #require(SafeListing.parse(listingPresentation(json)))
        let en = SafeListingFiles.table(listing, tree: nil, locale: Locale(identifier: "en_US"))
        let de = SafeListingFiles.table(listing, tree: nil, locale: Locale(identifier: "de_DE"))
        #expect(en.rows[0][0] == "große Datei.txt")
        #expect(de.rows[0][0] == "große Datei.txt")
        #expect(en.rows[0][2].contains("1.5"))
        #expect(de.rows[0][2].contains("1,5"))
        #expect(en.rows[0][3] != de.rows[0][3])
        // The sort key is locale-independent.
        #expect(en.sortKeys == de.sortKeys)
    }

    @Test func aPartialListingFlagsTheTable() throws {
        let json = #"{"partial":true,"entries":[{"path":"a","type":"file","bytes":1}]}"#
        let listing = try #require(SafeListing.parse(listingPresentation(json)))
        let table = SafeListingFiles.table(listing, tree: nil, locale: english)
        #expect(table.truncation == [.partialListing])
        #expect(table.columns.last == PreviewStrings.text(.listingModified), "Without a UTC marker the real modification instant is shown")
        #expect(SafeListingFiles.table(try parsedListing(archiveListingJSON), tree: nil, locale: english).truncation.isEmpty)
    }

    @Test func unknownKindsAreShownAsTheAdapterWroteThem() {
        #expect(SafeListingFormatting.kindLabel("package") == PreviewStrings.text(.listingKindPackage))
        #expect(SafeListingFormatting.kindLabel("symlink") == PreviewStrings.text(.summaryKindSymlink))
        #expect(SafeListingFormatting.kindLabel("vendor-kind") == "vendor-kind")
    }

    // MARK: Modes

    @Test func listingsOpenInFilesWithSourceSummaryAndTreeAvailable() {
        let modes = SafePreviewModes(listingPresentation(archiveListingJSON, format: .zip), locale: english)
        #expect(modes.available == [.source, .summary, .files, .tree])
        #expect(modes.initialMode(for: .zip) == .files)
        #expect(modes.files?.rows.count == 5)
        #expect(modes.tree?.nodeCount == 6)
        #expect(!modes.hasStructureFallback)
    }

    @Test func summariesThatAreNotListingsKeepSummaryAsTheirInitialMode() {
        let modes = SafePreviewModes(listingPresentation(#"{"archiveFormat":"directory","listedEntries":0,"entries":[]}"#), locale: english)
        #expect(modes.files == nil && modes.tree == nil)
        #expect(modes.available == [.source, .summary])
        #expect(modes.initialMode(for: .folder) == .summary)
    }

    @Test func listingModesDoNotAppearForOrdinaryJSONOrTables() {
        let json = SafePreviewModes(listingPresentation(archiveListingJSON, format: .json), locale: english)
        #expect(json.files == nil && json.tree == nil)
        #expect(json.initialMode(for: .json) == .source)
        let csv = TextPresentation(formatID: .csv, text: "a,b\n1,2\n", lineCount: 2, byteCount: 8, encoding: .utf8,
                                   redactionCount: 0, syntax: .commaSeparated)
        let table = SafePreviewModes(csv, locale: english)
        #expect(table.files == nil && table.tree == nil)
        #expect(table.initialMode(for: .csv) == .table)
    }

    @Test func concealmentThatBreaksTheJSONLeavesTheSafeSourceAndNoListingModes() {
        let broken = #"{"entries":[{"path":"••••"#
        let modes = SafePreviewModes(listingPresentation(broken, redactions: 1), locale: english)
        #expect(modes.files == nil && modes.tree == nil)
        #expect(modes.initialMode(for: .folder) == .source)
        #expect(modes.available == [.source])
    }

    // MARK: Privacy

    @Test func concealedNamesAreTheOnlyNamesEveryDerivedModelEverHolds() throws {
        let json = #"{"entries":[{"path":"••••","type":"file","bytes":3},{"path":"safe/••••","type":"file","bytes":4},{"path":"public.txt","type":"file","bytes":5}]}"#
        let modes = SafePreviewModes(listingPresentation(json, redactions: 2), locale: english)
        let table = try #require(modes.files)
        let tree = try #require(modes.tree)
        let everything = table.rows.flatMap { $0 } + table.columns + collectText(tree.roots)
        #expect(!everything.contains { $0.contains("synthetic-secret-value") })
        #expect(table.rows.map { $0[0] }.sorted() == ["public.txt", "safe/••••", "••••"].sorted())
        #expect(collectText(tree.roots).contains("••••"))
    }

    private func collectText(_ nodes: [SafeListingTree.Node]) -> [String] {
        nodes.flatMap { [$0.name, $0.path] + collectText($0.children) }
    }
}
