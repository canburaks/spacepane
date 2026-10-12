import AppKit
import Foundation
import Testing

@Suite("Concealment clipboard collector", .serialized)
@MainActor
struct ConcealmentSurfaceSupportTests {
    private typealias Surface = ConcealmentSurfaceSupport

    @Test(arguments: [false, true])
    func externalUTF16RepresentationKeepsBothByteOrdersAndExactSourceUnits(littleEndian: Bool) throws {
        let board = NSPasteboard(name: NSPasteboard.Name("q151-collector-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        let expected = "q151-e\u{301}😀\u{E0061}\u{E007F}"
        let bytes = Array(expected.utf16).flatMap { unit -> [UInt8] in
            let high = UInt8(truncatingIfNeeded: unit >> 8), low = UInt8(truncatingIfNeeded: unit)
            return littleEndian ? [low, high] : [high, low]
        }
        let data = Data(littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]) + Data(bytes)
        board.declareTypes([.string, Surface.externalUTF16PlainText], owner: nil)
        #expect(board.setString(expected, forType: .string))
        #expect(board.setData(data, forType: Surface.externalUTF16PlainText))
        let representation = try Surface.pasteboardRepresentation(board, type: Surface.externalUTF16PlainText)
        #expect(Array(representation.string.utf16) == Array(expected.utf16))
        let all = try Surface.pasteboardStrings(board)
        #expect(all.count == (try #require(board.types)).count && all.count >= 2)
        #expect(all.allSatisfy { Array($0.utf16) == Array(expected.utf16) })
    }

    @Test(arguments: [Data([0x61, 0x00]), Data([0xFF, 0xFE, 0x61])])
    func externalUTF16WithoutACompleteBOMAndCodeUnitFailsInspection(data: Data) {
        let board = NSPasteboard(name: NSPasteboard.Name("q151-collector-invalid-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        for type in [Surface.externalUTF16PlainText, Surface.legacyUTF16PlainText] {
            board.declareTypes([type], owner: nil)
            #expect(board.setData(data, forType: type))
            #expect(throws: Surface.Failure.self) {
                try Surface.pasteboardRepresentation(board, type: type)
            }
        }
    }
}
