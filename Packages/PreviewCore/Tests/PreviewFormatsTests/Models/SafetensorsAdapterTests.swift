import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

enum SafetensorsTestSupport {
    static func budget(input: Int = 16_777_216) -> PreviewBudget { PreviewBudget(maxInputBytes: input, maxMilliseconds: 30_000) }

    static func parse(_ data: Data, fileName: String? = nil, budget: PreviewBudget = SafetensorsTestSupport.budget()) throws
    -> ([String: Any], ParsedTextDocument) {
        var context = RequestContext(budget: budget)
        context.nameHint = fileName.map { PreviewNameHint(filename: $0, suffix: "safetensors") }
        let document = try SafetensorsAdapter().parse(DataByteSource(data), context: context)
        return (PackageTestSupport.object(document), document)
    }

    static func findings(_ data: Data) throws -> [PreviewFindingKind: Int] {
        let (_, document) = try parse(data)
        return Dictionary(uniqueKeysWithValues: document.findings.map { ($0.kind, $0.count) })
    }
}

@Suite("Safetensors summaries")
struct SafetensorsAdapterTests {
    private func tensors(_ names: [(String, [UInt64])], dtype: String = "F32") -> [SafetensorsFixtures.Tensor] {
        SafetensorsFixtures.laidOut(names.map { ($0.0, dtype, $0.1) })
    }

    @Test func ordinaryFileReportsItsFacts() throws {
        let data = SafetensorsFixtures.ordinary()
        let (summary, document) = try SafetensorsTestSupport.parse(data)
        #expect(summary["tensorCount"] as? Int == 2)
        #expect(summary["parameters"] as? Int == 40)
        #expect(summary["dtypes"] as? [String: Int] == ["F32": 1, "BF16": 1])
        #expect(summary["format"] as? String == "pt")
        #expect(summary["dataBytes"] as? Int == 128 + 16)
        #expect(summary["metadata"] as? [String: String] == ["format": "pt"])
        #expect(summary["partial"] as? Bool == false)
        #expect(summary["adapterKind"] == nil && summary["quantization"] == nil && summary["shard"] == nil)
        let headerLength = data.prefix(8).reversed().reduce(0) { $0 << 8 | Int($1) }
        #expect(summary["headerBytes"] as? Int == headerLength)
        #expect(document.origin == .summary)
        #expect(document.findings.isEmpty, "Header padding with spaces and an exact data size are ordinary")
        let listed = summary["tensors"] as? [[String: Any]] ?? []
        #expect(listed.count == 2)
        #expect(listed[0]["name"] as? String == "embed.weight" && listed[0]["dtype"] as? String == "F32")
        #expect(listed[0]["shape"] as? String == "4 × 8" && listed[0]["parameters"] as? Int == 32)
        #expect(listed[1]["dtype"] as? String == "BF16" && listed[1]["parameters"] as? Int == 8)
    }

    @Test func aHeaderWithNoMetadataOrNoTensorsIsFine() throws {
        let (summary, document) = try SafetensorsTestSupport.parse(SafetensorsFixtures.file([]))
        #expect(summary["tensorCount"] as? Int == 0 && summary["parameters"] as? Int == 0)
        #expect(summary["metadata"] == nil && summary["tensors"] == nil && summary["dtypes"] == nil)
        #expect(document.findings.isEmpty)
        let (withMetadata, _) = try SafetensorsTestSupport.parse(SafetensorsFixtures.ordinary(metadata: nil))
        #expect(withMetadata["metadata"] == nil && withMetadata["format"] == nil)
    }

    @Test func scalarsAndEmptyTensorsCountCorrectly() throws {
        let specs: [SafetensorsFixtures.Tensor] = SafetensorsFixtures.laidOut([("scalar", "F32", []), ("empty", "F32", [0, 5]), ("vector", "I8", [3])])
        let (summary, document) = try SafetensorsTestSupport.parse(SafetensorsFixtures.file(specs))
        #expect(summary["parameters"] as? Int == 4)
        let listed = summary["tensors"] as? [[String: Any]] ?? []
        #expect(listed.map { $0["parameters"] as? Int } == [1, 0, 3])
        #expect(listed[0]["shape"] as? String == "")
        #expect(document.findings.isEmpty)
    }

    @Test(arguments: [
        ("model-00002-of-00005.safetensors", "2 of 5"), ("diffusion_pytorch_model-00001-of-00002.safetensors", "1 of 2"),
        ("MODEL-00010-of-00012.SAFETENSORS", "10 of 12"), ("model-1-of-3.safetensors", "1 of 3")
    ])
    func shardPositionComesFromTheFileName(name: String, expected: String) throws {
        let (summary, _) = try SafetensorsTestSupport.parse(SafetensorsFixtures.ordinary(), fileName: name)
        #expect(summary["shard"] as? String == expected)
    }

    @Test(arguments: [
        "model.safetensors", "model-00007-of-00005.safetensors", "model-00000-of-00005.safetensors", "model-00001-of-00000.safetensors",
        "model-abc-of-def.safetensors", "model-00001-of-00002.bin", "-of-.safetensors", "model-00001-of-99999999.safetensors"
    ])
    func otherNamesGiveNoShard(name: String) throws {
        let (summary, _) = try SafetensorsTestSupport.parse(SafetensorsFixtures.ordinary(), fileName: name)
        #expect(summary["shard"] == nil)
    }

    @Test func peftLoRAIsRecognizedWithItsRank() throws {
        let specs = tensors([("base_model.model.layers.0.q_proj.lora_A.weight", [16, 64]), ("base_model.model.layers.0.q_proj.lora_B.weight", [64, 16]),
                             ("base_model.model.layers.1.q_proj.lora_A.weight", [16, 64]), ("base_model.model.layers.1.q_proj.lora_B.weight", [64, 16])])
        let (summary, _) = try SafetensorsTestSupport.parse(SafetensorsFixtures.file(specs))
        #expect(summary["adapterKind"] as? String == "LoRA" && summary["loraRank"] as? Int == 16)
    }

    @Test func kohyaLoRAWithAlphaIsRecognizedWithItsRank() throws {
        let specs = tensors([("lora_unet_up_blocks_0_attentions_0_proj_in.lora_down.weight", [8, 32]),
                             ("lora_unet_up_blocks_0_attentions_0_proj_in.lora_up.weight", [32, 8]),
                             ("lora_unet_up_blocks_0_attentions_0_proj_in.alpha", [])])
        let (summary, _) = try SafetensorsTestSupport.parse(SafetensorsFixtures.file(specs, metadata: [("ss_network_dim", "8")]))
        #expect(summary["adapterKind"] as? String == "LoRA" && summary["loraRank"] as? Int == 8)
    }

    @Test func mixedRanksKeepTheKindButNotTheRank() throws {
        let specs = tensors([("a.lora_A.weight", [4, 16]), ("a.lora_B.weight", [16, 4]), ("b.lora_A.weight", [8, 16]), ("b.lora_B.weight", [16, 8])])
        let (summary, _) = try SafetensorsTestSupport.parse(SafetensorsFixtures.file(specs))
        #expect(summary["adapterKind"] as? String == "LoRA" && summary["loraRank"] == nil)
    }

    @Test func halfAPairOrAlphaAloneIsNotLoRA() throws {
        for names in [["x.lora_A.weight"], ["x.lora_down.weight"], ["x.alpha"], ["lora_unet_up_blocks_0.weight", "lora_unet_down_blocks_0.weight"],
                      ["x.lora_B.weight", "y.lora_up.weight"], ["model.embed.weight"]] {
            let (summary, _) = try SafetensorsTestSupport.parse(SafetensorsFixtures.file(tensors(names.map { ($0, [4, 4]) })))
            #expect(summary["adapterKind"] == nil && summary["loraRank"] == nil, "\(names)")
        }
    }

    @Test func gptqAndAWQAreNamedOnlyWhenTheEvidenceIsClear() throws {
        func parts(_ prefix: String, _ suffixes: [String]) -> [(String, [UInt64])] { suffixes.map { (prefix + $0, [4]) } }
        let gptq = tensors(parts("model.layers.0.mlp.up_proj", [".qweight", ".qzeros", ".scales", ".g_idx"]))
        let awq = tensors(parts("model.layers.0.mlp.up_proj", [".qweight", ".qzeros", ".scales"]))
        let bare = tensors(parts("model.layers.0.mlp.up_proj", [".qweight"]))
        let noScales = tensors(parts("model.layers.0.mlp.up_proj", [".qweight", ".g_idx"]))
        let mixed = tensors(parts("a", [".qweight", ".qzeros", ".scales", ".g_idx"]) + parts("b", [".qweight", ".qzeros", ".scales"]))
        let gptqOnlyForSome = tensors(parts("a", [".qweight", ".qzeros", ".scales", ".g_idx"]) + parts("norm", [".weight"]))
        let expectations: [([SafetensorsFixtures.Tensor], String?)] = [(gptq, "GPTQ"), (awq, "AWQ"), (bare, nil), (noScales, nil), (mixed, nil), (gptqOnlyForSome, "GPTQ")]
        for (specs, expected) in expectations {
            let (summary, _) = try SafetensorsTestSupport.parse(SafetensorsFixtures.file(specs))
            #expect(summary["quantization"] as? String == expected)
        }
    }

    @Test func tensorListIsBoundedByTheListingCapacityAndTotalsStayExact() throws {
        let specs = SafetensorsFixtures.laidOut((0..<5_000).map { ("blk.\($0).w", "U8", [UInt64(4)]) })
        let (summary, document) = try SafetensorsTestSupport.parse(SafetensorsFixtures.file(specs))
        let capacity = PackageSummary.listingCapacity(PackageTestSupport.context)
        #expect((summary["tensors"] as? [[String: Any]])?.count == capacity)
        #expect(summary["tensorCount"] as? Int == 5_000 && summary["parameters"] as? Int == 20_000)
        #expect(summary["partial"] as? Bool == true)
        #expect(summary["dtypes"] as? [String: Int] == ["U8": 5_000])
        #expect(document.findings.isEmpty)
    }

    @Test func tensorNamesMadeOfControlCharactersAreListedInPartNotRefused() throws {
        let hostile = String(repeating: "\u{1}", count: 200)
        let specs = SafetensorsFixtures.laidOut((0..<2_000).map { ("\(hostile)\($0)", "U8", [UInt64(4)]) })
        let (summary, document) = try SafetensorsTestSupport.parse(SafetensorsFixtures.file(specs))
        let listed = (summary["tensors"] as? [[String: Any]])?.count ?? 0
        #expect(listed > 0 && listed < 2_000)
        #expect(summary["partial"] as? Bool == true && summary["parameters"] as? Int == 8_000)
        #expect(document.text.utf8.count < PreviewBudget.standard.maxOutputUTF8Bytes)
    }

    @Test func aThousandDistinctDtypeNamesAreCappedInTheDtypeTable() throws {
        let specs = (0..<1_000).map { SafetensorsFixtures.Tensor(name: "t\($0)", dtype: "X\($0)", shape: [1], begin: 0, end: 0) }
        let json = SafetensorsFixtures.headerJSON(specs)
        let (summary, _) = try SafetensorsTestSupport.parse(SafetensorsFixtures.file(json: json))
        #expect((summary["dtypes"] as? [String: Int])?.count == PackageSummary.maximumListItems)
        #expect(summary["tensorCount"] as? Int == 1_000)
    }

    @Test func metadataKeepsSixtyFourEntriesInFileOrderWithClippedValues() throws {
        let metadata = (0..<100).map { ("key\($0)", $0 == 0 ? String(repeating: "x", count: 5_000) : "v\($0)") }
        let (summary, document) = try SafetensorsTestSupport.parse(SafetensorsFixtures.file([], metadata: metadata))
        let shown = summary["metadata"] as? [String: String] ?? [:]
        #expect(shown.count == 64 && shown["key63"] == "v63" && shown["key64"] == nil)
        #expect(shown["key0"]?.utf8.count ?? 0 <= PackageSummary.maximumTextBytes && shown["key0"]?.hasSuffix("…") == true)
        #expect(document.text.range(of: "\"key0\"")!.lowerBound < document.text.range(of: "\"key1\"")!.lowerBound)
    }

    @Test func escapesAndNonASCIINamesAreDecoded() throws {
        let tensor = SafetensorsFixtures.Tensor(name: "w\u{E9}ight \u{1F642}", dtype: "F32", shape: [1], begin: 0, end: 4)
        var json = SafetensorsFixtures.headerJSON([tensor])
        json = json.replacingOccurrences(of: "w\u{E9}ight \u{1F642}", with: "w\\u00e9ight \\ud83d\\ude42")
        let (summary, _) = try SafetensorsTestSupport.parse(SafetensorsFixtures.file(json: json, tensors: [tensor]))
        #expect((summary["tensors"] as? [[String: Any]])?.first?["name"] as? String == "w\u{E9}ight \u{1F642}")
    }

    @Test func unknownDescriptorFieldsAndUnknownDtypesAreTolerated() throws {
        let json = "{\"a\":{\"dtype\":\"F99\",\"shape\":[2],\"data_offsets\":[0,6],\"extra\":{\"x\":[1,2.5e3,-1,null,true]}}}"
        let (summary, document) = try SafetensorsTestSupport.parse(SafetensorsFixtures.file(json: json, dataBytes: 6))
        #expect(summary["dtypes"] as? [String: Int] == ["F99": 1] && summary["parameters"] as? Int == 2)
        #expect(document.findings.isEmpty, "A dtype the table does not know has no size to contradict")
    }

    @Test func theBinaryPathGivesTheSameSummary() throws {
        let data = SafetensorsFixtures.ordinary()
        let viaBytes = try SafetensorsAdapter().parse(FileBytes(data: data), context: PackageTestSupport.context)
        let (_, viaSource) = try SafetensorsTestSupport.parse(data)
        #expect(viaBytes.text == viaSource.text)
    }
}
