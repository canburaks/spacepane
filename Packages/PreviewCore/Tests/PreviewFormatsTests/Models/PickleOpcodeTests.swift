import Foundation
import Testing
@testable import PreviewFormats

@Suite("Pickle opcode table and argument reading")
struct PickleOpcodeTests {
    /// Independent of the production table: the opcodes of protocols 0 to 5 as the pickle documentation lists them.
    private static let documentedBytes: Set<UInt8> = Set(Array("(.012FGIJKLMNPQRSTUVXabcdeghijlopqrstu)]}BC".utf8) + Array(0x80...0x98))

    @Test func theTableHoldsExactlyTheDocumentedOpcodes() {
        let known = Set((0...255).compactMap { PickleOpcode(rawValue: UInt8($0))?.rawValue })
        #expect(known == Self.documentedBytes)
        #expect(known.count == 68)
    }

    @Test(arguments: [
        (UInt8(ascii: "c"), 0), (UInt8(ascii: "X"), 1), (0x80, 2), (0x85, 2), (UInt8(ascii: "B"), 3),
        (0x8C, 4), (0x93, 4), (0x94, 4), (0x95, 4), (0x96, 5), (0x98, 5)
    ])
    func opcodesNameTheProtocolThatIntroducedThem(byte: UInt8, expected: Int) throws {
        #expect(try #require(PickleOpcode(rawValue: byte)).protocolVersion == expected)
    }

    private func reader<T>(_ bytes: [UInt8], _ body: (inout PickleReader) throws -> T) rethrows -> T {
        try bytes.withUnsafeBufferPointer { buffer in
            var reader = PickleReader(bytes: buffer, position: 0)
            return try body(&reader)
        }
    }

    @Test func integersAreLittleEndianAndBoundsChecked() throws {
        #expect(try reader([0x01, 0x02, 0x03, 0x04, 0x05]) { try $0.littleEndian(4) } == 0x0403_0201)
        #expect(try reader([0xFF]) { try $0.littleEndian(1) } == 255)
        #expect(throws: PickleBreak.self) { try reader([1, 2, 3]) { try $0.littleEndian(4) } }
        #expect(throws: PickleBreak.self) { try reader([]) { try $0.byte() } }
    }

    @Test func skippingNeverTrustsALength() throws {
        #expect(try reader([1, 2, 3, 4]) { try $0.skip(4) } == 0..<4)
        #expect(throws: PickleBreak.self) { try reader([1, 2, 3, 4]) { try $0.skip(5) } }
        #expect(throws: PickleBreak.self) { try reader([1, 2, 3, 4]) { try $0.skip(UInt64.max) } }
    }

    @Test func linesEndAtTheLineFeedAndNeedOne() throws {
        #expect(try reader(Array("os\nsystem\n".utf8)) { try ($0.line(), $0.line()) } == (0..<2, 3..<9))
        #expect(throws: PickleBreak.self) { try reader(Array("no newline".utf8)) { try $0.line() } }
        #expect(try reader(Array("12\n".utf8)) { try $0.decimalLine() } == 12)
        #expect(throws: PickleBreak.self) { try reader(Array("1x\n".utf8)) { try $0.decimalLine() } }
        #expect(throws: PickleBreak.self) { try reader(Array("\n".utf8)) { try $0.decimalLine() } }
    }

    private func quoted(_ literal: String) -> String? {
        reader(Array(literal.utf8)) { PickleText.quoted($0.bytes[0..<$0.bytes.count]) }
    }

    @Test func quotedStringsDecodeTheEscapesPythonDecodes() {
        #expect(quoted("'os'") == "os")
        #expect(quoted("\"os\"") == "os")
        #expect(quoted(#"'o\x73'"#) == "os")
        #expect(quoted(#"'\157s'"#) == "os")
        #expect(quoted(#"'a\tb\\c\'d'"#) == "a\tb\\c'd")
        #expect(quoted(#"'\q'"#) == #"\q"#)
        #expect(quoted("os") == nil)
        #expect(quoted("'os\"") == nil)
        #expect(quoted("'") == nil)
        #expect(quoted("''") == "")
    }

    @Test func rawUnicodeEscapeOnlyDecodesUnicodeEscapes() {
        func decode(_ bytes: [UInt8]) -> String { reader(bytes) { PickleText.rawUnicodeEscape($0.bytes[0..<$0.bytes.count]) } }
        #expect(decode(Array(#"o\U00000073"#.utf8)) == "os")
        #expect(decode(Array(#"a\x41\n"#.utf8)) == #"a\x41\n"#)
        #expect(decode([0xE9]) == "é")
        #expect(decode(Array(#"\u00zz"#.utf8)) == #"\u00zz"#)
    }

    @Test func decodedStringsAreBounded() {
        let long = "'" + String(repeating: "a", count: 10_000) + "'"
        #expect(quoted(long)?.utf8.count == PickleText.maximumBytes)
    }
}
