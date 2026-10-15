import AppKit
import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats
import PreviewTestSupport
@testable import PreviewRenderers

@MainActor
enum ConcealmentSurfaceSupport {
    enum Failure: Error {
        case unexpectedOutcome, uncollectedMode(String), uninspectedPasteboardType(String), tooManyAccessibilityElements
    }

    static let locale = Locale(identifier: "en_US")
    static let budget = PreviewBudget(maxMilliseconds: 30_000)
    static let coveredModes: Set<NativePreviewMode> = [
        .source, .outline, .records, .rendered, .table, .profile, .contents, .diagram, .invisibles
    ]
    // Explicitly outside this first tranche. Adding a mode needs both a fixture and a collector.
    static let remainingModes: Set<NativePreviewMode> = [
        .summary, .cues, .pages, .files, .tree, .references, .plot, .rows, .icon
    ]

    static func requiredModes(for kind: ConcealmentFixture.Kind) -> Set<NativePreviewMode> {
        switch kind {
        case .plainText, .sourceCode: [.source, .invisibles]
        case .json: [.source, .outline, .invisibles]
        case .jsonLines: [.source, .records, .invisibles]
        case .csv: [.source, .table, .profile, .invisibles]
        case .markdown: [.source, .rendered, .contents, .diagram, .invisibles]
        }
    }

    /// String equality folds canonical equivalence. Canary checks deliberately compare exact UTF-16.
    static func containsExact(_ needle: String, in text: String) -> Bool {
        let wanted = Array(needle.utf16), units = Array(text.utf16)
        guard !wanted.isEmpty, units.count >= wanted.count else { return false }
        return (0...(units.count - wanted.count)).contains { offset in
            units[offset..<(offset + wanted.count)].elementsEqual(wanted)
        }
    }

    static func assertSafe(_ strings: [String], fixture: ConcealmentFixture, surface: String,
                           sentinel: String? = nil) {
        assertSafe(strings, forbiddenStrings: fixture.forbiddenStrings, fixtureName: fixture.kind.rawValue,
                   surface: surface, sentinel: sentinel)
    }

    static func assertSafe(_ strings: [String], forbiddenStrings: [String], fixtureName: String,
                           surface: String, sentinel: String? = nil) {
        #expect(!strings.isEmpty, "\(fixtureName): empty \(surface) collector")
        for (index, canary) in forbiddenStrings.enumerated() {
            #expect(!strings.contains { containsExact(canary, in: $0) },
                    "\(fixtureName): canary \(index) escaped into \(surface)")
        }
        if let sentinel {
            #expect(strings.contains { containsExact(sentinel, in: $0) },
                    "\(fixtureName): safe sentinel did not reach \(surface)")
        }
    }

    static func preview(_ url: URL) async throws -> TextPresentation {
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
        guard case .ready(let presentation) = await pipeline.preview(url: url, budget: budget) else {
            Issue.record("Canary fixture did not produce a ready presentation")
            throw Failure.unexpectedOutcome
        }
        return presentation
    }

    static func modelStrings(_ modes: SafePreviewModes, presentation: TextPresentation,
                             mode: NativePreviewMode) throws -> [String] {
        func nodes(_ roots: [SafeOutlineNode]) -> [String] {
            roots.flatMap { [$0.name, $0.value] + nodes($0.children) }
        }
        func table(_ value: SafeTable) -> [String] {
            value.columns + value.rows.flatMap { $0 } + Array(value.cellDescriptions.values)
        }
        switch mode {
        case .source: return [presentation.text]
        case .invisibles: return [try #require(modes.invisibles).text]
        case .outline, .records, .summary, .cues:
            return nodes(try #require(modes.nodes(for: mode)))
        case .rendered, .contents:
            let document = try #require(modes.markdown)
            return [document.text] + document.headings.map(\.title)
        case .table, .profile:
            let strings = table(try #require(modes.displayedTable(for: mode)))
            return strings + (mode == .profile ? try #require(modes.profile).value.statusLines : [])
        case .diagram:
            let diagram = try #require(modes.diagram)
            let drawn = diagram.scene.primitives.flatMap { primitive -> [String] in
                switch primitive {
                case .text(let item): item.lines
                case .frame, .shape, .path, .slice, .swatch: []
                }
            }
            return drawn + diagram.accessibilityNodes.map(\.label) + diagram.connections.flatMap {
                [$0.source, $0.target] + ($0.label.map { [$0] } ?? [])
            }
        case .files: return table(try #require(modes.files))
        case .rows: return table(try #require(modes.sampleRows))
        case .endpoints: return table(try #require(modes.endpoints).table)
        case .tree:
            func tree(_ roots: [SafeListingTree.Node]) -> [String] {
                roots.flatMap { [$0.name, $0.path, $0.kind] + tree($0.children) }
            }
            return tree(try #require(modes.tree).roots)
        case .references:
            let bibliography = try #require(modes.references)
            let fields = bibliography.entries.flatMap { [$0.key, $0.type] + Array($0.fields.keys) + Array($0.fields.values) }
            return fields + BibliographyStyle.allCases.flatMap {
                BibliographyFormatter.document(bibliography, style: $0).map { [$0.text] + $0.headings.map(\.title) } ?? []
            }
        case .plot:
            let plot = try #require(modes.plot)
            return plot.positions.map { "\($0.longitude),\($0.latitude)" } + [NativePlotPreviewView.extentText(plot, locale: locale)]
        case .pages:
            #expect(!modes.pageImages.isEmpty)
            return modes.pageImages.enumerated().map {
                NativeImagePagesView.label(for: $0.element, number: $0.offset + 1, total: modes.pageImages.count, locale: locale)
            }
        case .icon:
            #expect(modes.images.contains { $0.role == .icon })
            return [PreviewStrings.text(.packageIconAccessibility, languagePreferences: ["en"])]
        }
    }

    static func attributedStrings(_ attributed: NSAttributedString) -> [String] {
        var result = [attributed.string]
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attributes, _, _ in
            for value in attributes.values { result.append(contentsOf: stringValues(value)) }
        }
        return result
    }

    private static func stringValues(_ value: Any?) -> [String] {
        switch value {
        case let text as String: return [text]
        case let url as URL: return [url.absoluteString, url.absoluteString.removingPercentEncoding ?? url.absoluteString]
        case let attributed as NSAttributedString: return attributedStrings(attributed)
        case let values as [Any]: return values.flatMap { stringValues($0) }
        default: return []
        }
    }

    /// Virtual accessibility elements, such as diagram node labels, are not NSView descendants.
    /// The bounded fixture walk visits both graphs and all realized table/outline cells.
    static func exposedStrings(in root: NSView) throws -> [String] {
        var strings: [String] = []
        var visited: Set<ObjectIdentifier> = []
        func visit(_ object: Any) throws {
            if let view = object as? NSView {
                guard visited.insert(ObjectIdentifier(view)).inserted else { return }
                guard visited.count <= 2048 else { throw Failure.tooManyAccessibilityElements }
                strings += [view.toolTip, view.accessibilityLabel(), view.accessibilityHelp()].compactMap { $0 }
                strings += stringValues(view.accessibilityValue())
                if let text = view as? NSTextView { strings += attributedStrings(text.attributedString()) }
                if let field = view as? NSTextField { strings += attributedStrings(field.attributedStringValue) }
                if let button = view as? NSButton { strings += attributedStrings(button.attributedTitle) }
                if let table = view as? NSTableView {
                    strings += table.tableColumns.map { $0.headerCell.stringValue }
                }
                for child in view.subviews { try visit(child) }
                for child in view.accessibilityChildren() ?? [] { try visit(child) }
            } else if let element = object as? NSAccessibilityElement {
                guard visited.insert(ObjectIdentifier(element)).inserted else { return }
                guard visited.count <= 2048 else { throw Failure.tooManyAccessibilityElements }
                strings += [element.accessibilityLabel(), element.accessibilityHelp()].compactMap { $0 }
                strings += stringValues(element.accessibilityValue())
                for child in element.accessibilityChildren() ?? [] { try visit(child) }
            }
        }
        try visit(root)
        return strings
    }

    static func realizeRows(in root: NSView) throws -> [String] {
        let views = [root] + descendants(of: root)
        for outline in views.compactMap({ $0 as? NSOutlineView }) {
            outline.expandItem(nil, expandChildren: true)
        }
        root.layoutSubtreeIfNeeded()
        var strings: [String] = []
        for table in ([root] + descendants(of: root)).compactMap({ $0 as? NSTableView }) where !table.isHiddenOrHasHiddenAncestor {
            #expect(table.numberOfRows > 0, "A required structured mode must realize rows")
            for row in 0..<table.numberOfRows {
                for column in 0..<table.numberOfColumns {
                    let cell = try #require(table.view(atColumn: column, row: row, makeIfNecessary: true))
                    strings += try exposedStrings(in: cell)
                }
            }
        }
        return strings
    }

    static let externalUTF16PlainText = NSPasteboard.PasteboardType("public.utf16-external-plain-text")
    static let legacyUTF16PlainText = NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x75743136")

    /// AppKit does not read every plain-text flavor as a selection. Decode the advertised external UTF-16
    /// bytes by their mandatory byte-order mark; keep the exact code units and rich native attributes.
    static func pasteboardRepresentation(_ board: NSPasteboard,
                                        type: NSPasteboard.PasteboardType) throws -> NSAttributedString {
        if type == externalUTF16PlainText || type == legacyUTF16PlainText {
            guard let data = board.data(forType: type), data.count >= 2, data.count.isMultiple(of: 2),
                  data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
                  let text = String(data: data, encoding: .utf16) else {
                throw Failure.uninspectedPasteboardType(type.rawValue)
            }
            return NSAttributedString(string: text)
        }
        let receiver = NSTextView(frame: .zero)
        if receiver.readSelection(from: board, type: type) { return receiver.attributedString() }
        if let text = board.string(forType: type) { return NSAttributedString(string: text) }
        if let data = board.data(forType: type), let text = String(data: data, encoding: .utf8) {
            return NSAttributedString(string: text)
        }
        throw Failure.uninspectedPasteboardType(type.rawValue)
    }

    /// Every advertised native clipboard representation must be read back or inspected as serialized text.
    static func pasteboardStrings(_ board: NSPasteboard) throws -> [String] {
        let types = try #require(board.types)
        #expect(types.contains(.string))
        var strings: [String] = []
        for type in types {
            strings += attributedStrings(try pasteboardRepresentation(board, type: type))
        }
        return strings
    }

    static func copyAllRepresentations(in host: InteractionHarness, mode: NativePreviewMode,
                                       fixture: ConcealmentFixture, sentinel: String) throws {
        func inspect(_ name: String, expectsSentinel: Bool = true) throws {
            assertSafe(try pasteboardStrings(host.pasteboard), fixture: fixture, surface: name,
                       sentinel: expectsSentinel ? sentinel : nil)
        }
        host.pasteboard.clearContents()
        #expect(host.view.copyAllSafeText())
        try inspect("Copy All \(mode)")
        if [.source, .rendered, .invisibles].contains(mode) {
            let stored = Array(host.view.textView.string.utf16)
            host.pasteboard.clearContents()
            host.view.textView.setSelectedRange(NSRange(location: 0, length: stored.count))
            host.view.textView.copy(nil)
            try inspect("native text selection \(mode)")
            #expect(Array(host.view.textView.string.utf16) == stored)
        } else if [.outline, .records, .summary, .cues].contains(mode) {
            let outline = try #require(host.view.outlineView.documentView as? NSOutlineView)
            let rows = IndexSet(integersIn: 0..<outline.numberOfRows)
            outline.selectRowIndexes(rows, byExtendingSelection: false)
            #expect(host.window.makeFirstResponder(outline))
            #expect(host.window.firstResponder === outline)
            host.pasteboard.clearContents()
            #expect(outline.performKeyEquivalent(with: host.keyEvent("c", .command)))
            try inspect("native outline selection \(mode)")
            for action in OutlineRowAction.allCases {
                host.pasteboard.clearContents()
                #expect(host.view.outlineView.perform(action, rows: rows))
                try inspect("outline \(action) \(mode)")
            }
        } else if [.table, .profile].contains(mode) {
            let table = try #require(host.view.contentView(for: mode) as? NativeTablePreviewView).tableView
            table.selectRowIndexes(IndexSet(integersIn: 0..<table.numberOfRows), byExtendingSelection: false)
            host.pasteboard.clearContents()
            table.copy(nil)
            try inspect("native table selection \(mode)")
        } else if mode == .contents {
            let contents = try #require(host.view.shownModeView as? MarkupContentsView)
            contents.tableView.selectRowIndexes(IndexSet(integersIn: 0..<contents.tableView.numberOfRows), byExtendingSelection: false)
            host.pasteboard.clearContents()
            contents.tableView.copy(nil)
            try inspect("native contents selection")
        }
        host.view.concealedTextPasteboard = host.pasteboard
        host.pasteboard.clearContents()
        if [.rendered, .invisibles].contains(mode) {
            host.view.copyConcealedText()
            try inspect("Copy Concealed Text \(mode)")
        } else {
            // The findings disclosure offers this action only beside derived rendered text.
            #expect(host.pasteboard.setString("prior private clipboard", forType: .string))
            let unchanged = host.pasteboard.changeCount
            host.view.copyConcealedText()
            #expect(host.pasteboard.changeCount == unchanged)
            #expect(host.pasteboard.string(forType: .string) == "prior private clipboard")
        }
        assertSafe(host.announcements.texts, fixture: fixture, surface: "copy and mode announcements")
    }
}
