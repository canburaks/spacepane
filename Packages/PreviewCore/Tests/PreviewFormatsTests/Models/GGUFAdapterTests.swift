import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// Shared by the GGUF suites.
enum GGUFTestSupport {
    static func budget(input: Int = 16_777_216) -> PreviewBudget { PreviewBudget(maxInputBytes: input, maxMilliseconds: 30_000) }

    static func parse(_ built: GGUFFixtures.Built, budget: PreviewBudget = GGUFTestSupport.budget()) throws -> ([String: Any], ParsedTextDocument) {
        let document = try GGUFAdapter().parse(DataByteSource(built.data), context: RequestContext(budget: budget))
        return (PackageTestSupport.object(document), document)
    }

    static func kinds(_ document: ParsedTextDocument) -> Set<PreviewFindingKind> { Set(document.findings.map(\.kind)) }
}

@Suite("GGUF summaries")
struct GGUFAdapterTests {
    @Test func ordinaryFileReportsItsFacts() throws {
        let (summary, document) = try GGUFTestSupport.parse(GGUFFixtures.ordinary())
        #expect(summary["name"] as? String == "Synthetic Test Model")
        #expect(summary["architecture"] as? String == "llama")
        #expect(summary["parameters"] as? Int == 4_352)
        #expect(summary["fileType"] as? String == "Q8_0")
        #expect(summary["bitsPerWeight"] as? String == "9.88")
        #expect(summary["contextLength"] as? Int == 4_096)
        #expect(summary["blockCount"] as? Int == 2)
        #expect(summary["vocabularySize"] as? Int == 4)
        #expect(summary["tokenizer"] as? String == "llama")
        #expect(summary["ggufVersion"] as? Int == 3)
        #expect(summary["alignment"] as? Int == 32)
        #expect(summary["tensorCount"] as? Int == 2)
        #expect(summary["metadataCount"] as? Int == 8)
        #expect(summary["partial"] as? Bool == false)
        #expect(summary["tensorTypes"] as? [String: Int] == ["F32": 1, "Q8_0": 1])
        #expect(document.origin == .summary)
        #expect(document.findings.isEmpty, "An ordinary complete file has nothing to report")
        let tensors = summary["tensors"] as? [[String: Any]] ?? []
        #expect(tensors.count == 2)
        #expect(tensors[0]["name"] as? String == "token_embd.weight" && tensors[0]["type"] as? String == "F32")
        #expect(tensors[0]["shape"] as? String == "64 × 4" && tensors[0]["parameters"] as? Int == 256)
        #expect(tensors[1]["type"] as? String == "Q8_0")
    }

    @Test func tensorTypesAreOrderedByCountThenCode() throws {
        let tensors = GGUFFixtures.laidOut([("a", [32], 8), ("b", [32], 0), ("c", [32], 8), ("d", [32], 1), ("e", [32], 1)])
        let (_, document) = try GGUFTestSupport.parse(GGUFFixtures.build(tensors: tensors))
        let text = document.text
        // Q8_0 and F16 tie at two tensors: the lower code comes first, then the single F32.
        #expect(text.range(of: "\"F16\": 2")!.lowerBound < text.range(of: "\"Q8_0\": 2")!.lowerBound)
        #expect(text.range(of: "\"Q8_0\": 2")!.lowerBound < text.range(of: "\"F32\": 1")!.lowerBound)
    }

    @Test(arguments: [(UInt32(2), true), (UInt32(3), false)])
    func versionTwoAndThreeAreRead(version: UInt32, bigEndian: Bool) throws {
        let (summary, _) = try GGUFTestSupport.parse(GGUFFixtures.ordinary(bigEndian: bigEndian, version: version))
        #expect(summary["ggufVersion"] as? Int == Int(version))
        #expect(summary["parameters"] as? Int == 4_352)
    }

    @Test func bigEndianFilesGiveTheSameSummaryAsLittleEndianOnes() throws {
        let (_, little) = try GGUFTestSupport.parse(GGUFFixtures.ordinary())
        let (_, big) = try GGUFTestSupport.parse(GGUFFixtures.ordinary(bigEndian: true))
        #expect(little.text == big.text)
    }

    @Test func versionOneAndNewerVersionsAreUnsupportedVariants() {
        for version: UInt32 in [1, 4, 5, 255] {
            let built = GGUFFixtures.ordinary(version: version)
            #expect(throws: PreviewFailure.unsupportedVariant, "version \(version)") { try GGUFTestSupport.parse(built) }
        }
        var bigEndianOne = GGUFFixtures.ordinary(bigEndian: true, version: 1)
        #expect(throws: PreviewFailure.unsupportedVariant) { try GGUFTestSupport.parse(bigEndianOne) }
        bigEndianOne.data.replaceSubrange(4..<8, with: [0, 0, 0, 0])
        #expect(throws: PreviewFailure.malformedDocument) { try GGUFTestSupport.parse(bigEndianOne) }
    }

    @Test func provenanceAndListFieldsAreSummarized() throws {
        let tags = (0..<20).map { "tag\($0)" }
        let (summary, _) = try GGUFTestSupport.parse(GGUFFixtures.build(metadata: [
            ("general.architecture", .string("qwen2")), ("general.size_label", .string("7B")),
            ("general.license", .string("apache-2.0")), ("general.author", .string("Example Lab")),
            ("general.organization", .string("Example Org")), ("general.quantized_by", .string("Example Quantizer")),
            ("general.base_model.count", .u32(2)),
            ("general.base_model.1.name", .string("Second Base")), ("general.base_model.0.name", .string("First Base")),
            ("general.tags", .strings(tags)), ("general.languages", .strings(["en", "tr"])),
            ("qwen2.attention.head_count", .u32(28)), ("qwen2.attention.head_count_kv", .u32(4)),
            ("qwen2.embedding_length", .u32(3584)), ("qwen2.expert_count", .u32(8)), ("qwen2.expert_used_count", .u32(2)),
            ("qwen2.context_length", .u32(32_768)), ("qwen2.block_count", .u32(28))
        ]))
        #expect(summary["sizeLabel"] as? String == "7B")
        #expect(summary["license"] as? String == "apache-2.0")
        #expect(summary["author"] as? String == "Example Lab")
        #expect(summary["organization"] as? String == "Example Org")
        #expect(summary["quantizedBy"] as? String == "Example Quantizer")
        #expect(summary["baseModels"] as? [String] == ["First Base", "Second Base"])
        #expect(summary["tags"] as? [String] == Array(tags.prefix(16)))
        #expect(summary["languages"] as? [String] == ["en", "tr"])
        #expect(summary["headCount"] as? Int == 28 && summary["headCountKV"] as? Int == 4)
        #expect(summary["embeddingLength"] as? Int == 3_584 && summary["blockCount"] as? Int == 28)
        #expect(summary["expertCount"] as? Int == 8 && summary["expertUsedCount"] as? Int == 2)
        #expect(summary["contextLength"] as? Int == 32_768)
        // The architecture's own numbers have fields of their own and are not repeated.
        let other = summary["otherMetadata"] as? [String: Any] ?? [:]
        #expect(other.keys.contains("general.base_model.count"))
        #expect(!other.keys.contains { $0.hasPrefix("qwen2.") })
    }

    @Test func fileTypesAreNamedAndUnknownOnesKeepTheirNumber() throws {
        for (code, name) in [(UInt32(0), "F32"), (1, "F16"), (15, "Q4_K_M"), (18, "Q6_K"), (32, "BF16"), (38, "MXFP4_MOE"), (777, "777")] {
            let (summary, _) = try GGUFTestSupport.parse(GGUFFixtures.build(metadata: [("general.file_type", .u32(code))]))
            #expect(summary["fileType"] as? String == name, "file type \(code)")
        }
    }

    @Test func otherMetadataKeepsSixtyFourScalarsInFileOrderAndShowsArraysAsCounts() throws {
        var metadata: [(String, GGUFFixtures.Value)] = [("zz.first", .f32(0.5)), ("zz.second", .bool(true)), ("zz.third", .i32(-7)),
                                                         ("zz.scores", .zeros(type: 6, count: 1_000)), ("zz.u64", .u64(UInt64.max))]
        metadata += (0..<100).map { ("zz.key\($0)", .u8(UInt8($0))) }
        let (summary, document) = try GGUFTestSupport.parse(GGUFFixtures.build(metadata: metadata))
        let other = summary["otherMetadata"] as? [String: Any] ?? [:]
        #expect(other.count == 64)
        #expect(other["zz.first"] as? String == "0.5")
        #expect(other["zz.second"] as? Bool == true)
        #expect(other["zz.third"] as? Int == -7)
        #expect(other["zz.scores"] as? Int == 1_000)
        #expect(other["zz.u64"] as? String == "18446744073709551615")
        #expect(other["zz.key58"] != nil && other["zz.key59"] == nil)
        let text = document.text
        let first = text.range(of: "zz.first")!.lowerBound
        #expect(first < text.range(of: "zz.key0\"")!.lowerBound)
        #expect(summary["metadataCount"] as? Int == 105)
    }

    @Test func chatTemplateIsClippedByWholeCharactersAndItsSizeIsReported() throws {
        let template = String(repeating: "é", count: 10_000)
        let (summary, _) = try GGUFTestSupport.parse(GGUFFixtures.build(metadata: [("tokenizer.chat_template", .string(template))]))
        let shown = try #require(summary["chatTemplate"] as? String)
        #expect(shown.hasSuffix("…") && shown.utf8.count <= 8_192)
        #expect(shown.dropLast().allSatisfy { $0 == "é" })
        #expect(summary["chatTemplateBytes"] as? Int == 20_000)
        let ordinary = "{% for m in messages %}{{ m.content }}{% endfor %}"
        let (short, _) = try GGUFTestSupport.parse(GGUFFixtures.build(metadata: [("tokenizer.chat_template", .string(ordinary))]))
        #expect(short["chatTemplate"] as? String == ordinary)
    }

    @Test func aTemplateOfControlCharactersStaysWithinTheSummaryLineLimit() throws {
        let template = String(repeating: "\u{1}", count: 8_000)
        let (_, document) = try GGUFTestSupport.parse(GGUFFixtures.build(metadata: [("tokenizer.chat_template", .string(template))]))
        let longest = document.text.split(separator: "\n", omittingEmptySubsequences: false).map(\.utf8.count).max() ?? 0
        #expect(longest <= PreviewBudget.standard.maxLineUTF8Bytes)
    }

    @Test func aMetadataStringAboveItsCapIsSkippedNotFatal() throws {
        let huge = String(repeating: "x", count: 1_048_577)
        let (summary, _) = try GGUFTestSupport.parse(GGUFFixtures.build(metadata: [
            ("general.name", .string(huge)), ("general.author", .string("Kept"))
        ]))
        #expect(summary["name"] == nil)
        #expect(summary["author"] as? String == "Kept")
    }

    @Test func aLargeVocabularyIsCountedWithoutBeingKept() throws {
        let tokens = (0..<300_000).map { "t\($0)" }
        let built = GGUFFixtures.build(metadata: [
            ("general.name", .string("Big Vocabulary")), ("tokenizer.ggml.tokens", .strings(tokens)),
            ("tokenizer.ggml.merges", .strings(tokens)), ("tokenizer.ggml.scores", .zeros(type: 6, count: 300_000)),
            ("general.architecture", .string("llama"))
        ])
        let (summary, document) = try GGUFTestSupport.parse(built, budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000))
        #expect(summary["vocabularySize"] as? Int == 300_000)
        #expect((summary["otherMetadata"] as? [String: Int])?["tokenizer.ggml.merges"] == 300_000)
        #expect((summary["otherMetadata"] as? [String: Int])?["tokenizer.ggml.scores"] == 300_000)
        #expect(document.text.utf8.count < 4_096, "No vocabulary entry reaches the summary")
    }

    @Test func tensorListIsBoundedByTheListingCapacityAndTotalsStayExact() throws {
        let specs = (0..<5_000).map { ("blk.\($0).w", [UInt64(32)], UInt32(0)) }
        let (summary, _) = try GGUFTestSupport.parse(GGUFFixtures.build(tensors: GGUFFixtures.laidOut(specs)))
        let capacity = PackageSummary.listingCapacity(PackageTestSupport.context)
        #expect((summary["tensors"] as? [[String: Any]])?.count == capacity)
        #expect(summary["tensorCount"] as? Int == 5_000)
        #expect(summary["parameters"] as? Int == 160_000)
        #expect(summary["partial"] as? Bool == true)
        #expect(summary["tensorTypes"] as? [String: Int] == ["F32": 5_000])
    }

    @Test func aFileWithNoTensorsHasNoBitsPerWeight() throws {
        let (summary, document) = try GGUFTestSupport.parse(GGUFFixtures.build(metadata: [("general.name", .string("Vocabulary only"))]))
        #expect(summary["parameters"] as? Int == 0)
        #expect(summary["bitsPerWeight"] == nil && summary["tensors"] == nil && summary["tensorTypes"] == nil)
        #expect(document.findings.isEmpty)
    }

    @Test func unknownTensorTypesAreShownByNumberAndSkipSizeFigures() throws {
        let tensors = [GGUFFixtures.Tensor(name: "mystery", dimensions: [10], type: 99, offset: 0)]
        let (summary, document) = try GGUFTestSupport.parse(GGUFFixtures.build(tensors: tensors, dataBytes: 0))
        #expect(summary["tensorTypes"] as? [String: Int] == ["type 99": 1])
        #expect((summary["tensors"] as? [[String: Any]])?.first?["type"] as? String == "type 99")
        #expect(summary["parameters"] as? Int == 10)
        #expect(summary["bitsPerWeight"] == nil)
        #expect(document.findings.isEmpty, "Without a known size nothing can be said about the data")
    }

    @Test func theBinaryPathGivesTheSameSummary() throws {
        let built = GGUFFixtures.ordinary()
        let viaBytes = try GGUFAdapter().parse(FileBytes(data: built.data), context: PackageTestSupport.context)
        let (_, viaSource) = try GGUFTestSupport.parse(built)
        #expect(viaBytes.text == viaSource.text)
    }

    @Test func customAlignmentMovesTheDataSection() throws {
        let tensors = GGUFFixtures.laidOut([("a", [64], 0), ("b", [64], 0)], alignment: 64)
        let built = GGUFFixtures.build(metadata: [("general.alignment", .u32(64))], tensors: tensors, alignment: 64)
        let (summary, document) = try GGUFTestSupport.parse(built)
        #expect(summary["alignment"] as? Int == 64)
        #expect(document.findings.isEmpty)
    }
}
