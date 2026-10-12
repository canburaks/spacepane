import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Property-list normalization output budgets")
struct PropertyListOutputBudgetTests {
    @Test func repeatedBinaryStringReferencesSpendCumulativeOutputBudget() throws {
        let repeatedCount = 4_096
        let string = String(repeating: "x", count: 512)
        let binary = repeatedStringBinaryPropertyList(string, count: repeatedCount)
        #expect(binary.count < 8_192)
        let context = RequestContext(budget: .init(maxOutputUTF8Bytes: 8_192))
        #expect(throws: PreviewFailure.outputTooLarge) {
            try PropertyListSourceAdapter().parse(FileBytes(data: binary), context: context)
        }
        // A failure from normalization establishes that serialization is never reached.
        // The native input has only two objects, but every reference spends output bytes.
        var normalizer = PropertyListNormalizer(context: context)
        #expect(throws: PreviewFailure.outputTooLarge) {
            try normalizer.value(Array(repeating: string, count: repeatedCount), depth: 1)
        }
        #expect(normalizer.nodes < 20)
    }

    @Test func preflightIncludesEscapedKeysUnicodeAndPrettyPrintOverhead() throws {
        let key = String((0..<32).compactMap(UnicodeScalar.init).map(Character.init)) + "\"\\/😀"
        let context = RequestContext(budget: .standard)
        var normalizer = PropertyListNormalizer(context: context)
        let input: [String: Any] = [key: ["line\n\t\"\\/\u{2028}😀", 42, true],
                                  "empty": [Any](), "blob": Data([1, 2]), "date": Date(timeIntervalSince1970: 0)]
        let normalized = try normalizer.value(input, depth: 1)
        let serialized = try JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys, .prettyPrinted, .fragmentsAllowed])
        #expect(normalizer.outputBound >= serialized.count)
        #expect(normalizer.outputBound <= context.budget.maxOutputUTF8Bytes)
        let binary = try PropertyListSerialization.data(fromPropertyList: input, format: .binary, options: 0)
        let parsed = try PropertyListSourceAdapter().parse(FileBytes(data: binary), context: context)
        #expect(parsed.text == String(decoding: serialized, as: UTF8.self))
    }

    /// Array object 0 references ASCII string object 1 repeatedly; the source stores the string once.
    private func repeatedStringBinaryPropertyList(_ value: String, count: Int) -> Data {
        var data = Data("bplist00".utf8)
        let arrayOffset = data.count
        data.append(0xAF)
        data.append(0x11)
        appendBigEndian(count, width: 2, to: &data)
        data.append(contentsOf: repeatElement(UInt8(1), count: count))
        let stringOffset = data.count
        data.append(0x5F)
        data.append(0x11)
        appendBigEndian(value.utf8.count, width: 2, to: &data)
        data.append(contentsOf: value.utf8)
        let tableOffset = data.count
        appendBigEndian(arrayOffset, width: 2, to: &data)
        appendBigEndian(stringOffset, width: 2, to: &data)
        data.append(contentsOf: repeatElement(UInt8(0), count: 6))
        data.append(contentsOf: [2, 1])
        appendBigEndian(2, width: 8, to: &data)
        appendBigEndian(0, width: 8, to: &data)
        appendBigEndian(tableOffset, width: 8, to: &data)
        return data
    }

    private func appendBigEndian(_ value: Int, width: Int, to data: inout Data) {
        for shift in stride(from: (width - 1) * 8, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
}
