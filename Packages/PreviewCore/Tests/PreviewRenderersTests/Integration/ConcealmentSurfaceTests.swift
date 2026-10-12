import AppKit
import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats
import PreviewTestSupport
@testable import PreviewRenderers
@testable import PreviewThumbnails

@Suite("Q151 first concealment surface canaries", .serialized)
@MainActor
struct ConcealmentSurfaceTests {
    private typealias Surface = ConcealmentSurfaceSupport

    private struct Directory {
        let url: URL
        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("q151-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
        func write(_ fixture: ConcealmentFixture, bytes: Data? = nil) throws -> URL {
            let file = url.appendingPathComponent(fixture.fileName)
            try (bytes ?? fixture.bytes).write(to: file)
            return file
        }
        func remove() { try? FileManager.default.removeItem(at: url) }
    }

    private func fixture(_ kind: ConcealmentFixture.Kind) throws -> ConcealmentFixture {
        try #require(ConcealmentFixtures.firstTranche.first { $0.kind == kind })
    }

    @Test func fixtureAndCollectorOraclesPreserveExactCanaryCodeUnitsAndDeclareTheMissingModes() {
        let a = ConcealmentFixtures.valueCanaries[0], b = ConcealmentFixtures.valueCanaries[1]
        #expect(a == b && Array(a.utf16) != Array(b.utf16))
        #expect(!Surface.containsExact(a, in: b) && !Surface.containsExact(b, in: a))
        for fixture in ConcealmentFixtures.firstTranche {
            let source = String(decoding: fixture.bytes, as: UTF8.self)
            #expect(Surface.containsExact(fixture.sentinel, in: source))
            #expect(fixture.sourceCanaries.allSatisfy { Surface.containsExact($0, in: source) })
        }
        let required = ConcealmentFixture.Kind.allCases.reduce(into: Set<NativePreviewMode>()) {
            $0.formUnion(Surface.requiredModes(for: $1))
        }
        #expect(required == Surface.coveredModes && required.count == 9)
        #expect(required.isDisjoint(with: Surface.remainingModes) && Surface.remainingModes.count == 9)
    }

    @Test(arguments: ConcealmentFixture.Kind.allCases)
    func realPipelineCanariesStayConcealedAcrossEveryRequiredModeAndNativeSurface(kind: ConcealmentFixture.Kind) async throws {
        let fixture = try fixture(kind)
        let directory = try Directory()
        defer { directory.remove() }
        let url = try directory.write(fixture)
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let presentation = try await Surface.preview(url)
        #expect(presentation.formatID == fixture.formatID && presentation.redactionCount >= 4)
        Surface.assertSafe([presentation.text], fixture: fixture, surface: "pipeline text", sentinel: fixture.sentinel)
        let modes = SafePreviewModes(presentation, locale: Surface.locale)
        #expect(Set(modes.available) == Surface.requiredModes(for: kind))
        let host = InteractionHarness(width: 900, height: 700)
        defer { host.release() }
        host.view.display(.ready(presentation), locale: Surface.locale, resetsContentState: true)
        for mode in modes.available {
            let index = try #require(host.view.displayedModes.firstIndex(of: mode))
            #expect(host.view.selectMode(number: index + 1))
            #expect(host.view.modeControl.selectedSegment == index)
            let content = try #require(host.view.contentView(for: mode))
            Surface.assertSafe(try Surface.modelStrings(modes, presentation: presentation, mode: mode),
                               fixture: fixture, surface: "derived \(mode)", sentinel: fixture.sentinel)
            let cells = try Surface.realizeRows(in: content)
            Surface.assertSafe(try Surface.exposedStrings(in: content) + cells,
                               fixture: fixture, surface: "visible/AX \(mode)", sentinel: fixture.sentinel)
            Surface.assertSafe(try Surface.exposedStrings(in: host.view), fixture: fixture, surface: "complete native tree \(mode)")
            #expect(!host.view.findingsBanner.detailsButton.isHidden)
            host.view.findingsBanner.detailsButton.performClick(nil)
            #expect(host.view.findingsBanner.isExpanded && !host.view.findingsBanner.detailScrollView.isHidden)
            #expect(host.view.findingsBanner.rowLabels.count == presentation.findings.count)
            Surface.assertSafe(try Surface.exposedStrings(in: host.view.findingsBanner), fixture: fixture,
                               surface: "expanded findings disclosure \(mode)")
            host.view.findingsBanner.detailsButton.performClick(nil)
            try Surface.copyAllRepresentations(in: host, mode: mode, fixture: fixture, sentinel: fixture.sentinel)
        }
        let wording = presentation.findings.flatMap {
            [FindingText.message(for: $0, locale: Surface.locale)] + (FindingText.detail(for: $0, locale: Surface.locale).map { [$0] } ?? [])
        }
        Surface.assertSafe(wording, fixture: fixture, surface: "every finding message/detail")
        Surface.assertSafe(host.view.findingsBanner.rowLabels.map(\.stringValue), fixture: fixture, surface: "findings banner")
        #expect(try Data(contentsOf: url) == fixture.bytes)
        #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path) == [fixture.fileName])
    }

    @Test(arguments: ConcealmentFixture.Kind.allCases)
    func independentThumbnailServiceWithholdsByDefaultAndItsDrawingPathContainsOnlyConcealedText(kind: ConcealmentFixture.Kind) async throws {
        let fixture = try fixture(kind)
        let directory = try Directory()
        defer { directory.remove() }
        let url = try directory.write(fixture)
        let geometry = try #require(ThumbnailGeometry(maximumSize: CGSize(width: 768, height: 768), scale: 1))
        var limits = ThumbnailLimits.standard
        limits.textBudget = Surface.budget
        let defaults = ContentThumbnailService(registrations: StandardFormatAdapters.registrations,
            preferences: .fixed(.defaults), limits: limits)
        guard case .generic(.withheldConcealedContent) = await defaults.result(for: url, geometry: geometry).outcome else {
            Issue.record("A credential-bearing canary must be withheld by the shipping concealment policy")
            return
        }
        // Existing injectable limits lift withholding only for these synthetic fixtures. Privacy filtering
        // remains the actual pipeline's policy, so final drawing is examined rather than skipped.
        limits.maximumConcealedValues = .max
        limits.withholdsSecretShapes = false
        let drawing = ContentThumbnailService(registrations: StandardFormatAdapters.registrations,
            preferences: .fixed(.defaults), limits: limits)
        guard case .content(let scene) = await drawing.result(for: url, geometry: geometry).outcome else {
            Issue.record("The synthetic drawing fixture must produce an inspectable thumbnail scene")
            return
        }
        Surface.assertSafe(scene.content.drawnStrings, fixture: fixture, surface: "thumbnail scene", sentinel: fixture.sentinel)
        #expect(try Data(contentsOf: url) == fixture.bytes)
    }

    @Test(arguments: [ConcealmentFixture.Kind.json, .csv, .markdown])
    func replacingRealSourceClearsPriorModeCellsTooltipsAndAccessibility(kind: ConcealmentFixture.Kind) async throws {
        let fixture = try fixture(kind)
        let directory = try Directory()
        defer { directory.remove() }
        let url = try directory.write(fixture)
        let host = InteractionHarness(width: 900, height: 700)
        defer { host.release() }
        host.view.display(.ready(try await Surface.preview(url)), locale: Surface.locale, resetsContentState: true)
        for index in host.view.displayedModes.indices {
            #expect(host.view.selectMode(number: index + 1))
            _ = try Surface.realizeRows(in: try #require(host.view.contentView(for: host.view.displayedModes[index])))
        }
        let nextSentinel = "Q151Next"
        let replacement = Data(String(decoding: fixture.bytes, as: UTF8.self)
            .replacingOccurrences(of: fixture.sentinel, with: nextSentinel).utf8)
        _ = try directory.write(fixture, bytes: replacement)
        let current = try await Surface.preview(url)
        host.view.display(.ready(current), locale: Surface.locale, resetsContentState: true)
        #expect(Set(host.view.displayedModes) == Surface.requiredModes(for: kind))
        for index in host.view.displayedModes.indices {
            let mode = host.view.displayedModes[index]
            #expect(host.view.selectMode(number: index + 1))
            let content = try #require(host.view.contentView(for: mode))
            let cells = try Surface.realizeRows(in: content)
            let strings = try Surface.exposedStrings(in: host.view) + cells
            Surface.assertSafe(strings, fixture: fixture, surface: "replacement \(mode)", sentinel: nextSentinel)
            #expect(!strings.contains { Surface.containsExact(fixture.sentinel, in: $0) }, "Stale source reached replacement \(mode)")
            try Surface.copyAllRepresentations(in: host, mode: mode, fixture: fixture, sentinel: nextSentinel)
        }
        #expect(try Data(contentsOf: url) == replacement)
    }

    @Test func surfaceCollectorSeesVirtualAccessibilityAndAttributedMetadataRatherThanOnlyViews() throws {
        let root = Q151VirtualAccessibilityView(frame: .zero)
        let virtual = NSAccessibilityElement()
        virtual.setAccessibilityRole(.staticText)
        virtual.setAccessibilityLabel("virtual-AX-canary")
        virtual.setAccessibilityParent(root)
        root.virtualChildren = [virtual]
        let field = NSTextField(labelWithString: "safe field")
        field.attributedStringValue = NSAttributedString(string: "safe field", attributes: [
            .toolTip: "attributed-tooltip-canary", .link: URL(string: "https://example.invalid/attributed-link-canary")!
        ])
        root.addSubview(field)
        let strings = try Surface.exposedStrings(in: root)
        for canary in ["virtual-AX-canary", "attributed-tooltip-canary", "attributed-link-canary"] {
            #expect(strings.contains { Surface.containsExact(canary, in: $0) })
        }
    }
}

@MainActor
private final class Q151VirtualAccessibilityView: NSView {
    var virtualChildren: [NSAccessibilityElement] = []
    override func accessibilityChildren() -> [Any]? { virtualChildren }
}
