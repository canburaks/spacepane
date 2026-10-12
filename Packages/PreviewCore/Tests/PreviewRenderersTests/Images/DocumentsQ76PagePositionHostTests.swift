import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

// Decision 027, Q-76: the preview's limits slot shows the page column's "Page n of m" as soon as the column has a
// top page, including when a second document reuses the column (its first report arrives while the header is
// being restyled) and when the presentation locale changes the wording.

@Suite("Pages position in the preview's limits slot", .serialized)
@MainActor
struct DocumentsQ76PagePositionHostTests {
    private let english = Locale(identifier: "en_US")

    private func comic(_ pages: Int) -> TextPresentation {
        presentation(.comicBook, text: "{}", syntax: .json, images: testPages(pages))
    }

    @Test func theFirstDocumentShowsItsPositionAfterLayout() throws {
        let host = InteractionHarness(width: 600, height: 400)
        defer { host.release() }
        host.view.display(.ready(comic(10)), locale: english)
        host.view.layoutSubtreeIfNeeded()
        try #require(host.view.selectedMode == .pages)
        #expect(host.view.limitsLabel.stringValue.contains("Page 1 of 10"), "\(host.view.limitsLabel.stringValue)")
    }

    @Test func aSecondDocumentInTheSameColumnShowsItsOwnPositionAtOnce() throws {
        let host = InteractionHarness(width: 600, height: 400)
        defer { host.release() }
        host.view.display(.ready(comic(10)), locale: english)
        host.view.layoutSubtreeIfNeeded()
        try #require(host.view.limitsLabel.stringValue.contains("Page 1 of 10"))
        // The column already has its size, so the new document's first page is reported during the restyle.
        host.view.display(.ready(comic(20)), locale: english)
        #expect(host.view.limitsLabel.stringValue.contains("Page 1 of 20"), "\(host.view.limitsLabel.stringValue)")
        #expect(!host.view.limitsLabel.stringValue.contains("of 10"), "\(host.view.limitsLabel.stringValue)")
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.limitsLabel.stringValue.contains("Page 1 of 20"), "\(host.view.limitsLabel.stringValue)")
    }

    @Test func aNewLocaleRewordsTheShownPositionAtOnce() throws {
        let host = InteractionHarness(width: 600, height: 400)
        defer { host.release() }
        // The wording follows the process language; only the digits follow the presentation locale, so a total
        // with a grouping separator is what tells the two apart ("1,200" against "1.200").
        let large = presentation(.comicBook, text: "{\"pageCount\": 1200}", syntax: .json, images: testPages(10))
        host.view.display(.ready(large), locale: english)
        host.view.layoutSubtreeIfNeeded()
        try #require(host.view.limitsLabel.stringValue.contains("1,200"), "\(host.view.limitsLabel.stringValue)")
        host.view.display(.ready(large), locale: Locale(identifier: "de_DE"))
        #expect(host.view.limitsLabel.stringValue.contains("1.200"), "\(host.view.limitsLabel.stringValue)")
        #expect(!host.view.limitsLabel.stringValue.contains("1,200"), "\(host.view.limitsLabel.stringValue)")
    }
}
