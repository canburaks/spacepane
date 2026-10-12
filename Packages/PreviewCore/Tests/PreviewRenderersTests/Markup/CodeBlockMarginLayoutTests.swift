import AppKit
import Testing
@testable import PreviewRenderers

@Suite("Q73 code margin geometry and candidate bounds")
struct CodeBlockMarginLayoutTests {
    @Test func thirtyTwoClearPointsFitTheCompleteNativeButtonOnEitherTrailingSide() throws {
        let viewport = NSRect(x: 0, y: 0, width: 600, height: 400)
        let card = NSRect(x: 32, y: 20, width: 536, height: 40)
        let column = NSRect(x: 32, y: 0, width: 536, height: 400)
        for left in [false, true] {
            let frame = try #require(CodeBlockMarginPlacement.frame(card: card, column: column,
                                                                    viewport: viewport, trailingOnLeft: left))
            #expect(frame.width == 22 && frame.height == 22 && viewport.contains(frame))
            #expect(!frame.intersects(column))
            #expect(left ? frame.maxX <= column.minX - 5 : frame.minX >= column.maxX + 5)
        }
    }

    @Test func insufficientMarginsAndOffscreenAnchorsCannotOverlayOrCreateStickyButtons() {
        let viewport = NSRect(x: 0, y: 100, width: 360, height: 300)
        let column = NSRect(x: 12, y: 100, width: 336, height: 300)
        let card = NSRect(x: 12, y: 120, width: 336, height: 80)
        for left in [false, true] {
            #expect(CodeBlockMarginPlacement.frame(card: card, column: column, viewport: viewport, trailingOnLeft: left) == nil)
        }
        let wideColumn = NSRect(x: 60, y: 100, width: 240, height: 300)
        for top in [50.0, 90.0, 390.0, 401.0] {
            #expect(CodeBlockMarginPlacement.frame(card: NSRect(x: 60, y: top, width: 240, height: 200),
                                                   column: wideColumn, viewport: viewport, trailingOnLeft: false) == nil)
        }
        #expect(CodeBlockMarginPlacement.frame(card: .zero, column: wideColumn, viewport: viewport, trailingOnLeft: false) == nil)
        #expect(CodeBlockMarginPlacement.frame(card: NSRect(x: 60, y: CGFloat.infinity, width: 240, height: 200),
                                               column: wideColumn, viewport: viewport, trailingOnLeft: false) == nil)
    }

    @Test func exactMarginThresholdUsesTheChosenSideAndDoesNotMirrorDocumentContent() throws {
        let viewport = NSRect(x: 0, y: 0, width: 600, height: 400)
        let column = NSRect(x: 40, y: 0, width: 529, height: 400)
        let card = NSRect(x: 40, y: 20, width: 529, height: 40)
        #expect(CodeBlockMarginPlacement.frame(card: card, column: column, viewport: viewport, trailingOnLeft: false) == nil)
        let frame = try #require(CodeBlockMarginPlacement.frame(card: card, column: column, viewport: viewport, trailingOnLeft: true))
        #expect(frame.maxX < card.minX && frame.minY == card.minY + 4)
    }

    @Test func candidatesRetainExplicitBodyIdentityAcrossGapsAndHalfOpenEdges() {
        let blocks = [MarkupCodeBlock(range: NSRange(location: 10, length: 4), language: .swift),
                      .init(range: NSRange(location: 16, length: 1), language: nil),
                      .init(range: NSRange(location: 20, length: 10), language: .python)]
        let index = CodeBlockMarginIndex(blocks, textLength: 40)
        #expect(index.candidates(overlapping: NSRange(location: 0, length: 10)).isEmpty)
        #expect(index.candidates(overlapping: NSRange(location: 13, length: 1)) == [0])
        #expect(index.candidates(overlapping: NSRange(location: 14, length: 2)).isEmpty)
        #expect(index.candidates(overlapping: NSRange(location: 16, length: 1)) == [1])
        #expect(index.candidates(overlapping: NSRange(location: 17, length: 4)) == [2])
        #expect(index.candidates(overlapping: NSRange(location: 12, length: 10)) == [0, 1, 2])
    }

    @Test func malformedUnorderedAndOverlappingBodiesCannotCorruptTheVisibleIndex() {
        let blocks = [MarkupCodeBlock(range: NSRange(location: NSNotFound, length: Int.max), language: nil),
                      .init(range: NSRange(location: 0, length: 0), language: nil),
                      .init(range: NSRange(location: 10, length: 4), language: .swift),
                      .init(range: NSRange(location: 11, length: 10), language: nil),
                      .init(range: NSRange(location: 5, length: 1), language: nil),
                      .init(range: NSRange(location: 40, length: 1), language: nil),
                      .init(range: NSRange(location: 20, length: 2), language: .python)]
        let index = CodeBlockMarginIndex(blocks, textLength: 40)
        #expect(index.candidates(overlapping: NSRange(location: 0, length: 40)) == [2, 6])
        for range in [NSRange(location: NSNotFound, length: Int.max), NSRange(location: 39, length: 2),
                      NSRange(location: 0, length: 0)] { #expect(index.candidates(overlapping: range).isEmpty) }
    }

    @Test func aLateViewportRequestsOnlyItsVisibleBodiesFromALargeMetadataIndex() {
        let blocks = (0..<10_000).map { MarkupCodeBlock(range: NSRange(location: $0 * 4, length: 2), language: nil) }
        let index = CodeBlockMarginIndex(blocks, textLength: 40_000)
        #expect(index.candidates(overlapping: NSRange(location: 39_991, length: 9)) == [9_998, 9_999])
    }
}
