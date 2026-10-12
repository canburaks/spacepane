import CoreGraphics
import Testing
@testable import PreviewRenderers

// Decision 027, Q-76 (review DM-22): where the symbol and words of a failed page frame sit. Pure geometry.

@Suite("Failed page frame layout")
struct DocumentsQ76PageFailureLayoutTests {
    private func layout(_ width: CGFloat, _ height: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> PageFailureLayout {
        PageFailureLayout(picture: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func aRoomyFrameCentersTheSymbolOverTheWords() throws {
        let picture = CGRect(x: 0, y: 0, width: 200, height: 280)
        let result = layout(200, 280)
        let label = try #require(result.label)
        #expect(result.symbol.width == PageFailureLayout.symbolSide && result.symbol.height == PageFailureLayout.symbolSide)
        #expect(abs(result.symbol.midX - picture.midX) <= 1)
        #expect(label.minY >= result.symbol.maxY + PageFailureLayout.gap - 0.5)
        #expect(label.width == picture.width - 2 * PageFailureLayout.inset)
        #expect(label.height == PageFailureLayout.labelHeight)
        #expect(picture.contains(result.symbol) && picture.contains(label))
        // The pair is centered vertically: the same space above the symbol as below the words.
        #expect(abs((result.symbol.minY - picture.minY) - (picture.maxY - label.maxY)) <= 1)
    }

    @Test func wordsNeedEnoughWidthAndHeightAndTheSymbolNeedsRoomToo() {
        let inset = 2 * PageFailureLayout.inset
        let labelWidth = PageFailureLayout.minimumLabelWidth + inset
        let labelHeight = PageFailureLayout.symbolSide + PageFailureLayout.gap + PageFailureLayout.labelHeight + inset
        #expect(layout(labelWidth, labelHeight).label != nil)
        #expect(layout(labelWidth - 1, labelHeight).label == nil)
        #expect(layout(labelWidth, labelHeight - 1).label == nil)
        // Without room for the words the symbol stays, centered in the frame.
        let narrow = layout(labelWidth - 1, labelHeight)
        #expect(narrow.symbol.width == PageFailureLayout.symbolSide)
        #expect(abs(narrow.symbol.midY - labelHeight / 2) <= 1)
        let smallest = PageFailureLayout.minimumSymbolSide + inset
        #expect(layout(smallest, smallest).symbol.width == PageFailureLayout.minimumSymbolSide)
        #expect(layout(smallest - 1, smallest).symbol == .zero)
        #expect(layout(smallest, smallest - 1).symbol == .zero && layout(smallest, smallest - 1).label == nil)
    }

    @Test func theSymbolShrinksToWhatTheFrameAllowsAndNeverBelowTheMinimum() {
        let inset = 2 * PageFailureLayout.inset
        #expect(layout(40, 40).symbol.width == 40 - inset)
        #expect(layout(500, 30).symbol.height == 30 - inset)
        #expect(layout(0, 0).symbol == .zero && layout(0, 0).label == nil)
        #expect(layout(-5, 100).symbol == .zero)
    }

    @Test func aFrameAwayFromTheOriginMovesTheSameArrangement() throws {
        let origin = layout(200, 280)
        let moved = layout(200, 280, x: 30, y: 50)
        #expect(moved.symbol == origin.symbol.offsetBy(dx: 30, dy: 50))
        let movedLabel = try #require(moved.label)
        let originLabel = try #require(origin.label)
        #expect(movedLabel == originLabel.offsetBy(dx: 30, dy: 50))
    }

    @Test func noSizeMakesTheSymbolAndWordsOverlapOrLeaveTheFrame() {
        for width in stride(from: CGFloat(0), through: 320, by: 9) {
            for height in stride(from: CGFloat(0), through: 320, by: 11) {
                let picture = CGRect(x: 0, y: 0, width: width, height: height)
                let result = layout(width, height)
                if !result.symbol.isEmpty { #expect(picture.contains(result.symbol), "\(width) x \(height)") }
                if let label = result.label {
                    #expect(picture.contains(label), "\(width) x \(height)")
                    #expect(!result.symbol.intersects(label), "\(width) x \(height)")
                }
            }
        }
    }
}
