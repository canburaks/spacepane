import AppKit
import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats
import PreviewTestSupport
@testable import PreviewRenderers
@testable import PreviewThumbnails

private final class Q151ThumbnailCounter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

private struct Q151NoReadThumbnailReader: PreviewFileReading {
    let reads: Q151ThumbnailCounter
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        reads.increment(); throw PreviewFailure.unsupportedFormat
    }
    func openRandomAccess(url: URL, context: RequestContext) throws -> any PreviewByteSource {
        reads.increment(); throw PreviewFailure.unsupportedFormat
    }
}

@Suite("Q151 remaining mode identity canaries", .serialized)
@MainActor
struct ConcealmentRemainingSurfaceTests {
    typealias Fixture = ConcealmentRemainingFixture
    private typealias Surface = ConcealmentSurfaceSupport
    private struct Entry: Equatable {
        let bytes: Data?, modified: Date?, created: Date?, permissions: Int?, size: Int?
    }
    private struct Directory {
        let url: URL
        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("q151-modes-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
        func write(_ fixture: Fixture) throws -> URL {
            for (path, bytes) in fixture.files {
                let file = url.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: file)
            }
            return url.appendingPathComponent(fixture.fileName)
        }
        /// Include every child directory and file, bytes, and mutation-relevant metadata.
        func snapshot() throws -> [String: Entry] {
            var entries: [String: Entry] = [:]
            let enumerator = try #require(FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]))
            for case let child as URL in enumerator {
                let path = String(child.path.dropFirst(url.path.count + 1))
                let attributes = try FileManager.default.attributesOfItem(atPath: child.path)
                let regular = try child.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                entries[path] = Entry(bytes: regular ? try Data(contentsOf: child) : nil,
                    modified: attributes[.modificationDate] as? Date, created: attributes[.creationDate] as? Date,
                    permissions: (attributes[.posixPermissions] as? NSNumber)?.intValue,
                    size: (attributes[.size] as? NSNumber)?.intValue)
            }
            return entries
        }
        func remove() { try? FileManager.default.removeItem(at: url) }
    }
    private func newModes(_ kind: Fixture.Kind) -> Set<NativePreviewMode> {
        switch kind {
        case .environment: [.summary]
        case .subtitle: [.cues]
        case .archive: [.summary, .files, .tree]
        case .bibliography: [.references]
        case .geoJSON: [.summary, .plot]
        case .parquet: [.summary, .rows]
        case .notebook: [.pages]
        case .application: [.summary, .icon]
        }
    }
    private func safe(_ strings: [String], fixture: Fixture, surface: String, sentinel: String? = nil) {
        Surface.assertSafe(strings, forbiddenStrings: fixture.forbiddenStrings,
                           fixtureName: fixture.kind.rawValue, surface: surface, sentinel: sentinel)
    }
    private func textualSentinel(for mode: NativePreviewMode, fixture: Fixture) -> String? {
        if [.plot, .pages, .icon].contains(mode) { return nil }
        // A Parquet schema describes columns, not the dictionary values retained in its row sample.
        if fixture.kind == .parquet && mode == .table { return "api_token" }
        return fixture.sentinel
    }

    @Test func newFixturesCarryIndependentCanariesAndCoverExactlyTheNineRemainingModeIdentities() throws {
        let modes = Fixture.Kind.allCases.reduce(into: Set<NativePreviewMode>()) { $0.formUnion(newModes($1)) }
        #expect(modes == Surface.remainingModes && modes.count == 9)
        for kind in Fixture.Kind.allCases {
            let fixture = try ConcealmentRemainingFixtures.make(kind)
            for canary in fixture.forbiddenStrings {
                let bytes = Data(canary.utf8)
                #expect(fixture.files.values.contains { $0.range(of: bytes) != nil })
                for image in fixture.encodedImages { #expect(image.range(of: bytes) != nil) }
            }
            if kind == .parquet { try inspectIndependentParquet(fixture) }
        }
    }
    private func inspectIndependentParquet(_ fixture: Fixture) throws {
        let bytes = try #require(fixture.files[fixture.fileName])
        #expect(bytes.count == DataFixtures.parquetRows.count)
        #expect(bytes.range(of: Data(DataFixtures.secret.utf8)) == nil)
        for canary in ConcealmentFixtures.valueCanaries {
            let wanted = Data(canary.utf8)
            var matches = 0, cursor = bytes.startIndex
            while let range = bytes.range(of: wanted, in: cursor..<bytes.endIndex) { matches += 1; cursor = range.upperBound }
            #expect(matches == 1)
        }
        let document = try ParquetAdapter().parse(RecordingByteSource(bytes), context: RequestContext(budget: Surface.budget))
        let root = try #require(try JSONSerialization.jsonObject(with: Data(document.text.utf8)) as? [String: Any])
        let sample = try #require(root["rowSample"] as? [String: Any])
        #expect(sample["columnNames"] as? [String] == ["id", "name", "score", "flag", "day", "amount", "ts", "api_token", "blob"])
        let rows = try #require(sample["rows"] as? [[Any]])
        #expect(rows.count == 5 && rows.allSatisfy { $0.count == 9 })
        #expect(rows.compactMap { $0[0] as? String } == ["10", "20", "30", "40", "50"])
        #expect(rows[0][1] as? String == fixture.sentinel && rows[3][1] as? String == fixture.sentinel)
        for (index, row) in [0, 2, 3, 4].enumerated() {
            let expected = ConcealmentFixtures.valueCanaries[index] + String(repeating: " ", count: 22 - ConcealmentFixtures.valueCanaries[index].utf8.count)
            #expect(Array((try #require(rows[row][7] as? String)).utf16) == Array(expected.utf16))
        }
    }

    @Test(arguments: Fixture.Kind.allCases)
    func actualAdaptersConcealOrOmitCanariesBeforeEveryAvailableModelAndNativeSurface(kind: Fixture.Kind) async throws {
        let fixture = try ConcealmentRemainingFixtures.make(kind)
        let directory = try Directory(); defer { directory.remove() }
        let url = try directory.write(fixture), before = try directory.snapshot()
        let presentation = try await Surface.preview(url)
        #expect(presentation.formatID == fixture.formatID)
        if fixture.expectsConcealment { #expect(presentation.redactionCount > 0) }
        else { #expect(presentation.redactionCount == 0) }
        safe([presentation.text], fixture: fixture, surface: "pipeline", sentinel: fixture.sentinel)
        let modes = SafePreviewModes(presentation, locale: Surface.locale)
        #expect(newModes(kind).isSubset(of: Set(modes.available)))
        let host = InteractionHarness(width: 900, height: 700); defer { host.release() }
        host.view.chromeScheduler = ManualChromeScheduler()
        host.view.display(.ready(presentation), locale: Surface.locale, resetsContentState: true)
        for mode in modes.available {
            let index = try #require(host.view.displayedModes.firstIndex(of: mode))
            #expect(host.view.selectMode(number: index + 1))
            let content = try #require(host.view.contentView(for: mode))
            safe(try Surface.modelStrings(modes, presentation: presentation, mode: mode), fixture: fixture,
                 surface: "derived \(mode)", sentinel: textualSentinel(for: mode, fixture: fixture))
            safe(try Surface.exposedStrings(in: content) + Surface.realizeRows(in: content), fixture: fixture,
                 surface: "visible/AX \(mode)", sentinel: textualSentinel(for: mode, fixture: fixture))
            safe(try Surface.exposedStrings(in: host.view), fixture: fixture, surface: "all retained native views \(mode)")
            try inspectStructuralSentinel(mode, content: content, modes: modes, fixture: fixture)
            try copy(in: host, content: content, mode: mode, fixture: fixture)
        }
        if !presentation.findings.isEmpty {
            host.view.findingsBanner.detailsButton.performClick(nil)
            #expect(host.view.findingsBanner.isExpanded)
            safe(try Surface.exposedStrings(in: host.view.findingsBanner), fixture: fixture, surface: "expanded findings")
            safe(presentation.findings.flatMap {
                [FindingText.message(for: $0, locale: Surface.locale)] + (FindingText.detail(for: $0, locale: Surface.locale).map { [$0] } ?? [])
            }, fixture: fixture, surface: "finding messages and details")
        }
        #expect(try directory.snapshot() == before)
    }
    private func inspectStructuralSentinel(_ mode: NativePreviewMode, content: NSView, modes: SafePreviewModes,
                                           fixture: Fixture) throws {
        if mode == .plot {
            let plot = try #require(modes.plot)
            #expect(plot.paths == [[.init(longitude: 11, latitude: 22), .init(longitude: 33, latitude: 44)]])
            #expect(plot.points.isEmpty)
            let view = try #require(content as? NativePlotPreviewView)
            #expect(!view.captionLabel.stringValue.isEmpty && view.canvas.accessibilityValue() != nil)
        } else if mode == .pages {
            #expect(modes.pageImages.count == 1 && modes.pageImages[0].isValid)
            #expect(modes.pageImages[0].data == fixture.encodedImages[0])
            let pages = [content] + descendants(of: content)
            let captions = pages.compactMap { ($0 as? ImagePageFrameView)?.caption }
            #expect(captions.count == 1 && captions.allSatisfy { !$0.isEmpty })
            safe(captions, fixture: fixture, surface: "drawn page captions")
        } else if mode == .icon {
            let icon = try #require(modes.images.first { $0.role == .icon })
            #expect(icon.isValid && icon.data == fixture.encodedImages[0])
            let images = ([content] + descendants(of: content)).compactMap { $0 as? NSImageView }
            #expect(images.count == 1 && images[0].image != nil)
        }
    }

    private func copy(in host: InteractionHarness, content: NSView, mode: NativePreviewMode, fixture: Fixture) throws {
        func inspect(_ name: String, expectsSentinel: Bool = true) throws {
            safe(try Surface.pasteboardStrings(host.pasteboard), fixture: fixture, surface: name,
                 sentinel: expectsSentinel ? fixture.sentinel : nil)
        }
        host.pasteboard.clearContents()
        #expect(host.view.copyAllSafeText())
        try inspect("facade Copy All \(mode)", expectsSentinel: mode != .table || fixture.kind != .parquet)
        if [.source, .rendered, .invisibles].contains(mode) {
            let text = host.view.textView
            try #require(text.pasteboard === host.pasteboard)
            text.setSelectedRange(NSRange(location: 0, length: text.string.utf16.count))
            host.pasteboard.clearContents()
            text.copy(nil); try inspect("native text selection \(mode)")
        } else if [.outline, .summary, .cues].contains(mode) {
            try #require(host.view.outlineView.pasteboard === host.pasteboard)
            let outline = try #require(host.view.outlineView.documentView as? NSOutlineView)
            outline.selectRowIndexes(IndexSet(integersIn: 0..<outline.numberOfRows), byExtendingSelection: false)
            #expect(host.window.makeFirstResponder(outline))
            host.pasteboard.clearContents()
            #expect(outline.performKeyEquivalent(with: host.keyEvent("c", .command)))
            try inspect("native outline selection \(mode)")
            let rows = IndexSet(integersIn: 0..<outline.numberOfRows)
            for action in OutlineRowAction.allCases {
                host.pasteboard.clearContents()
                #expect(host.view.outlineView.perform(action, rows: rows))
                // Environment keys and source paths need not contain the safe value sentinel.
                try inspect("outline \(action) \(mode)", expectsSentinel: false)
            }
        } else if [.files, .rows, .table].contains(mode) {
            let table: NativeTablePreviewView
            if let files = content as? NativeListingFilesView { table = files.table }
            else if let rows = content as? NativeRowsPreviewView { table = rows.table }
            else { table = try #require(content as? NativeTablePreviewView) }
            try #require(table.pasteboard === host.pasteboard)
            table.tableView.selectRowIndexes(IndexSet(integersIn: 0..<table.tableView.numberOfRows), byExtendingSelection: false)
            host.pasteboard.clearContents()
            table.tableView.copy(nil)
            try inspect("native selected rows \(mode)", expectsSentinel: mode != .table)
        } else if let tree = content as? NativeListingTreeView {
            try #require(tree.pasteboard === host.pasteboard)
            tree.outlineView.selectRowIndexes(IndexSet(integersIn: 0..<tree.outlineView.numberOfRows), byExtendingSelection: false)
            #expect(host.window.makeFirstResponder(tree.outlineView))
            host.pasteboard.clearContents()
            #expect(tree.outlineView.performKeyEquivalent(with: host.keyEvent("c", .command)))
            try inspect("native tree selection")
        } else if let references = content as? MarkupReferencesView {
            let base: NSTextView = references.textView
            let text = try #require(base as? PreviewTextView)
            try #require(text.pasteboard === host.pasteboard)
            for index in BibliographyStyle.allCases.indices {
                references.styleControl.selectedSegment = index
                #expect(references.styleControl.sendAction(references.styleControl.action, to: references.styleControl.target))
                #expect(references.selectedStyle == BibliographyStyle.allCases[index])
                safe(try Surface.exposedStrings(in: references), fixture: fixture, surface: "References style \(index)", sentinel: fixture.sentinel)
                text.setSelectedRange(NSRange(location: 0, length: text.string.utf16.count))
                host.pasteboard.clearContents()
                text.copy(nil); try inspect("native References selection \(index)")
            }
        } else if let contents = content as? MarkupContentsView {
            try #require(contents.pasteboard === host.pasteboard)
            contents.tableView.selectRowIndexes(IndexSet(integersIn: 0..<contents.tableView.numberOfRows), byExtendingSelection: false)
            host.pasteboard.clearContents()
            contents.tableView.copy(nil); try inspect("native Contents selection")
        }
        // Plot, Pages and Icon have no selection-copy action. Copy All above remains a real facade write.
        host.view.concealedTextPasteboard = host.pasteboard
        if [.rendered, .invisibles].contains(mode) {
            host.pasteboard.clearContents()
            host.view.copyConcealedText()
            try inspect("Copy Concealed Text \(mode)")
        } else {
            let previous = try #require(host.pasteboard.string(forType: .string))
            let before = host.pasteboard.changeCount
            host.view.copyConcealedText()
            #expect(host.pasteboard.changeCount == before)
            #expect(Array((host.pasteboard.string(forType: .string) ?? "").utf16) == Array(previous.utf16))
        }
        safe(host.announcements.texts, fixture: fixture, surface: "copy and mode announcements")
    }

    @Test(arguments: Fixture.Kind.allCases)
    func independentThumbnailServicePreservesShippingWithholdingAndInspectsItsActualSceneKind(kind: Fixture.Kind) async throws {
        let fixture = try ConcealmentRemainingFixtures.make(kind)
        let directory = try Directory(); defer { directory.remove() }
        let url = try directory.write(fixture), before = try directory.snapshot()
        let geometry = try #require(ThumbnailGeometry(maximumSize: CGSize(width: 768, height: 768), scale: 1))
        var limits = ThumbnailLimits.standard; limits.textBudget = Surface.budget
        let contentFree = [.environment, .archive, .geoJSON, .application].contains(kind)
        let descriptor = try #require(FormatCatalog.standard.descriptor(for: fixture.formatID))
        #expect(descriptor.thumbnail == (contentFree ? .generic : .content))
        if contentFree {
            let reads = Q151ThumbnailCounter(), factories = Q151ThumbnailCounter()
            let registrations = StandardFormatAdapters.registrations.filter { $0.formatID != fixture.formatID } + [
                AdapterRegistration(formatID: fixture.formatID) { factories.increment(); return TextAdapter() }
            ]
            let defaults = ContentThumbnailService(registrations: registrations, preferences: .fixed(.defaults),
                reader: Q151NoReadThumbnailReader(reads: reads), limits: limits)
            guard case .generic(.genericPolicy) = await defaults.result(for: url, geometry: geometry).outcome else {
                Issue.record("Shipping content-free policy must answer before reading or constructing an adapter"); return
            }
            #expect(reads.value == 0 && factories.value == 0)
        } else {
            let defaults = ContentThumbnailService(registrations: StandardFormatAdapters.registrations, preferences: .fixed(.defaults), limits: limits)
            guard case .generic(.withheldConcealedContent) = await defaults.result(for: url, geometry: geometry).outcome else {
                Issue.record("Expected shipping concealment withholding"); return
            }
        }
        // Test-only admission lets the canary suite inspect the real pipeline and scene builder behind the
        // shipped generic policy. Only this descriptor's thumbnail field changes; production stays generic.
        let catalog = contentFree ? contentThumbnailCatalog(for: fixture.formatID) : .standard
        if contentFree && fixture.expectsConcealment {
            let defaults = ContentThumbnailService(registrations: StandardFormatAdapters.registrations,
                preferences: .fixed(.defaults), catalog: catalog, limits: limits)
            guard case .generic(.withheldConcealedContent) = await defaults.result(for: url, geometry: geometry).outcome else {
                Issue.record("Test-only content admission must still withhold concealed content"); return
            }
        }
        limits.maximumConcealedValues = .max; limits.withholdsSecretShapes = false
        let inspect = ContentThumbnailService(registrations: StandardFormatAdapters.registrations,
            preferences: .fixed(.defaults), catalog: catalog, limits: limits)
        let outcome = await inspect.result(for: url, geometry: geometry).outcome
        if kind == .notebook {
            let presentation = try await Surface.preview(url)
            #expect((try? JSONSerialization.jsonObject(with: Data(presentation.text.utf8))) == nil)
            guard case .generic(.nothingToDraw) = outcome else {
                Issue.record("Concealed notebook JSON must fail closed, without drawing its saved figure"); return
            }
        } else if [.archive, .geoJSON].contains(kind) {
            guard case .generic(.summaryText) = outcome else { Issue.record("Summary text must never draw"); return }
        } else {
            guard case .content(let scene) = outcome else { Issue.record("Expected inspectable synthetic thumbnail content: \(String(describing: outcome))"); return }
            switch scene.content {
            case .picture(let picture):
                #expect(kind == .application && picture.role == .icon && picture.image.width > 0 && picture.image.height > 0)
                #expect(scene.content.drawnStrings.isEmpty) // Pictures intentionally draw no metadata strings.
            case .grid(let grid):
                #expect(kind == .parquet && !grid.headers.isEmpty && grid.rowCount > 0)
                safe(scene.content.drawnStrings, fixture: fixture, surface: "thumbnail grid")
            case .text:
                #expect(kind != .application && kind != .parquet)
                safe(scene.content.drawnStrings, fixture: fixture, surface: "thumbnail text", sentinel: fixture.sentinel)
            }
        }
        #expect(try directory.snapshot() == before)
    }

    private func contentThumbnailCatalog(for format: FormatID) -> FormatCatalog {
        FormatCatalog(descriptors: FormatCatalog.standard.descriptors.map { descriptor in
            guard descriptor.id == format else { return descriptor }
            return FormatDescriptor(id: descriptor.id, contentTypes: descriptor.contentTypes,
                suffixAliases: descriptor.suffixAliases, group: descriptor.group,
                presentation: descriptor.presentation, thumbnail: .content,
                nameKey: descriptor.nameKey, descriptionKey: descriptor.descriptionKey,
                filenameAliases: descriptor.filenameAliases, filenamePrefixes: descriptor.filenamePrefixes,
                defaultEnabled: descriptor.defaultEnabled, primaryView: descriptor.primaryView)
        }, unresolvedContentTypes: FormatCatalog.standard.unresolvedContentTypes)
    }

    @Test func validNotebookSourceWithImageMetadataDrawsOnlySafeCellText() async throws {
        let fixture = try ConcealmentRemainingFixtures.notebookWithSafeSourceAndImageMetadata()
        let directory = try Directory(); defer { directory.remove() }
        let url = try directory.write(fixture), before = try directory.snapshot()
        for canary in fixture.forbiddenStrings {
            #expect(fixture.encodedImages[0].range(of: Data(canary.utf8)) != nil)
        }
        #expect(fixture.encodedImages[0].base64EncodedString().hasSuffix("="))
        let presentation = try await Surface.preview(url)
        #expect(presentation.images.count == 1 && presentation.images[0].data == fixture.encodedImages[0])
        let input = try #require(fixture.files[fixture.fileName])
        let json = try JSONSourceAdapter().parse(DecodedText(text: String(decoding: input, as: UTF8.self),
            encoding: .utf8, byteCount: input.count), context: RequestContext(budget: Surface.budget))
        #expect(json.sensitiveRanges.isEmpty)
        let parsed = try JupyterNotebookAdapter().parse(FileBytes(data: input), context: RequestContext(budget: Surface.budget))
        #expect(parsed.sensitiveRanges.isEmpty)
        #expect(presentation.redactionCount == 0)
        let root = try #require(try JSONSerialization.jsonObject(with: Data(presentation.text.utf8)) as? [String: Any])
        let cells = try #require(root["cells"] as? [[String: Any]])
        #expect(cells.first?["source"] as? [String] == [fixture.sentinel + "\n"])
        let geometry = try #require(ThumbnailGeometry(maximumSize: CGSize(width: 768, height: 768), scale: 1))
        var limits = ThumbnailLimits.standard; limits.textBudget = Surface.budget
        let service = ContentThumbnailService(registrations: StandardFormatAdapters.registrations,
            preferences: .fixed(.defaults), limits: limits)
        let outcome = await service.result(for: url, geometry: geometry).outcome
        guard case .content(let scene) = outcome, case .text = scene.content else {
            Issue.record("Valid notebook must draw cell text under the shipped text-only picture policy: \(String(describing: outcome))"); return
        }
        safe(scene.content.drawnStrings, fixture: fixture, surface: "valid notebook thumbnail", sentinel: fixture.sentinel)
        #expect(try directory.snapshot() == before)
    }

    @Test(arguments: Fixture.Kind.allCases)
    func replacingActualInputClearsPriorCellsMetadataAndCopyOutputAcrossRemainingModes(kind: Fixture.Kind) async throws {
        let original = try ConcealmentRemainingFixtures.make(kind)
        let directory = try Directory(); defer { directory.remove() }
        let url = try directory.write(original)
        let host = InteractionHarness(width: 900, height: 700); defer { host.release() }
        host.view.chromeScheduler = ManualChromeScheduler()
        host.view.display(.ready(try await Surface.preview(url)), locale: Surface.locale, resetsContentState: true)
        for index in host.view.displayedModes.indices {
            #expect(host.view.selectMode(number: index + 1))
            _ = try Surface.realizeRows(in: try #require(host.view.contentView(for: host.view.displayedModes[index])))
        }
        let next = try ConcealmentRemainingFixtures.make(kind, sentinel: kind == .parquet ? "Q151N" : "Q151Next")
        _ = try directory.write(next)
        let before = try directory.snapshot()
        let current = try await Surface.preview(url)
        host.view.display(.ready(current), locale: Surface.locale, resetsContentState: true)
        let modes = SafePreviewModes(current, locale: Surface.locale)
        #expect(newModes(kind).isSubset(of: Set(modes.available)))
        for index in host.view.displayedModes.indices {
            let mode = host.view.displayedModes[index]
            #expect(host.view.selectMode(number: index + 1))
            let content = try #require(host.view.contentView(for: mode))
            let visible = try Surface.exposedStrings(in: content) + Surface.realizeRows(in: content)
            safe(visible, fixture: next, surface: "replacement \(mode)", sentinel: textualSentinel(for: mode, fixture: next))
            let retained = try Surface.exposedStrings(in: host.view)
            #expect(retained.allSatisfy { !Surface.containsExact(original.sentinel, in: $0) })
            safe(retained, fixture: next, surface: "all retained replacement views")
            try copy(in: host, content: content, mode: mode, fixture: next)
            #expect(try Surface.pasteboardStrings(host.pasteboard).allSatisfy { !Surface.containsExact(original.sentinel, in: $0) })
        }
        #expect(try directory.snapshot() == before)
    }
}
