import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("GGUF findings and privacy")
struct GGUFFindingsTests {
    private func kinds(_ built: GGUFFixtures.Built) throws -> [PreviewFindingKind: Int] {
        let (_, document) = try GGUFTestSupport.parse(built)
        return Dictionary(uniqueKeysWithValues: document.findings.map { ($0.kind, $0.count) })
    }

    private func findings(metadata: [(String, GGUFFixtures.Value)]) throws -> [PreviewFindingKind: Int] {
        try kinds(GGUFFixtures.build(metadata: metadata))
    }

    // MARK: Incomplete files

    @Test func dataCutShortIsReportedWithTheNumberOfTensorsBeyondTheFile() throws {
        let tensors = GGUFFixtures.laidOut([("a", [64], 0), ("b", [64], 0), ("c", [64], 0)])
        let complete = GGUFFixtures.build(tensors: tensors)
        #expect(try kinds(complete).isEmpty)
        let oneByteShort = GGUFFixtures.build(tensors: tensors, dataBytes: GGUFFixtures.total(tensors) - 1)
        #expect(try kinds(oneByteShort) == [.modelIncomplete: 1])
        let secondCut = GGUFFixtures.build(tensors: tensors, dataBytes: 256 + 10)
        #expect(try kinds(secondCut) == [.modelIncomplete: 2])
        let noData = GGUFFixtures.build(tensors: tensors, dataBytes: 0)
        #expect(try kinds(noData) == [.modelIncomplete: 3])
    }

    @Test func extraBytesAfterTheTensorsAreNotReported() throws {
        let tensors = GGUFFixtures.laidOut([("a", [64], 0)])
        #expect(try kinds(GGUFFixtures.build(tensors: tensors, dataBytes: GGUFFixtures.total(tensors) + 4_096)).isEmpty)
    }

    @Test func theFindingsCarryNoLinesAndNoDetail() throws {
        let tensors = GGUFFixtures.laidOut([("a", [64], 0)])
        let (_, document) = try GGUFTestSupport.parse(GGUFFixtures.build(tensors: tensors, dataBytes: 0))
        let finding = try #require(document.findings.first)
        #expect(finding.lines.isEmpty && finding.detail == .none && finding.severity == .caution)
    }

    // MARK: Layout

    @Test func overlappingTensorRangesAreInconsistent() throws {
        let tensors = [GGUFFixtures.Tensor(name: "a", dimensions: [64], type: 0, offset: 0),
                       GGUFFixtures.Tensor(name: "b", dimensions: [64], type: 0, offset: 64)]
        #expect(try kinds(GGUFFixtures.build(tensors: tensors, dataBytes: 512)) == [.modelInconsistentLayout: 1])
        let sameOffset = [GGUFFixtures.Tensor(name: "a", dimensions: [64], type: 0, offset: 0),
                          GGUFFixtures.Tensor(name: "b", dimensions: [8], type: 0, offset: 0)]
        #expect(try kinds(GGUFFixtures.build(tensors: sameOffset, dataBytes: 512)) == [.modelInconsistentLayout: 1])
    }

    @Test func offsetsOffTheAlignmentAreInconsistent() throws {
        let tensors = [GGUFFixtures.Tensor(name: "a", dimensions: [8], type: 0, offset: 0),
                       GGUFFixtures.Tensor(name: "b", dimensions: [8], type: 0, offset: 33)]
        #expect(try kinds(GGUFFixtures.build(tensors: tensors, dataBytes: 512)) == [.modelInconsistentLayout: 1])
    }

    @Test func aFirstDimensionThatIsNotWholeBlocksIsInconsistentAndHasNoKnownSize() throws {
        let tensors = [GGUFFixtures.Tensor(name: "a", dimensions: [33, 2], type: 2, offset: 0)]
        #expect(try kinds(GGUFFixtures.build(tensors: tensors, dataBytes: 0)) == [.modelInconsistentLayout: 1])
    }

    @Test func unknownTypesStillHaveTheirOffsetsChecked() throws {
        let tensors = [GGUFFixtures.Tensor(name: "a", dimensions: [8], type: 77, offset: 5)]
        #expect(try kinds(GGUFFixtures.build(tensors: tensors, dataBytes: 0)) == [.modelInconsistentLayout: 1])
    }

    @Test func gapsBetweenAlignedTensorsAndEmptyTensorsAreNotReported() throws {
        let tensors = [GGUFFixtures.Tensor(name: "a", dimensions: [8], type: 0, offset: 0),
                       GGUFFixtures.Tensor(name: "empty", dimensions: [0], type: 0, offset: 0),
                       GGUFFixtures.Tensor(name: "b", dimensions: [8], type: 0, offset: 256)]
        #expect(try kinds(GGUFFixtures.build(tensors: tensors, dataBytes: 256 + 32)).isEmpty)
    }

    @Test func everyKnownTypeSizeMatchesTheIndependentFixtureTable() throws {
        let types: [(UInt32, [UInt64])] = [(0, [10]), (1, [10]), (30, [10]), (2, [64]), (8, [64]), (12, [512]), (14, [512])]
        let tensors = GGUFFixtures.laidOut(types.enumerated().map { ("t\($0.offset)", $0.element.1, $0.element.0) })
        // Exactly the bytes the fixture table needs: the production table must agree, or one side reports a cut.
        #expect(try kinds(GGUFFixtures.build(tensors: tensors)).isEmpty)
        #expect(try kinds(GGUFFixtures.build(tensors: tensors, dataBytes: GGUFFixtures.total(tensors) - 1)) == [.modelIncomplete: 1])
    }

    // MARK: Hidden characters

    @Test func eachHiddenClassInAChatTemplateGivesItsOwnFinding() throws {
        let template = "Hi\u{202E}x\u{200B}\u{200B}y\u{E0041}\u{E0042}\u{E0043}z a\u{E0100} \u{E000}{{ m }}"
        let found = try findings(metadata: [("tokenizer.chat_template", .string(template))])
        #expect(found == [.hiddenBidirectionalControls: 1, .hiddenZeroWidth: 2, .hiddenUnicodeTags: 3,
                          .hiddenVariationSelectors: 1, .hiddenPrivateUse: 1])
    }

    @Test func hiddenFindingsHaveNoLinesAndNoDecodedText() throws {
        let (_, document) = try GGUFTestSupport.parse(GGUFFixtures.build(metadata: [
            ("tokenizer.chat_template", .string("a\u{E0041}\u{E0042}b\u{202E}"))
        ]))
        #expect(!document.findings.isEmpty)
        for finding in document.findings { #expect(finding.lines.isEmpty && finding.detail == .none) }
        #expect(document.findings.first { $0.kind == .hiddenUnicodeTags }?.severity == .warning)
        #expect(document.findings.first { $0.kind == .hiddenZeroWidth } == nil)
    }

    @Test func hiddenCharactersBeyondTheShownPartOfATemplateAreStillCounted() throws {
        let template = String(repeating: "a", count: 20_000) + "\u{200B}"
        let (summary, document) = try GGUFTestSupport.parse(GGUFFixtures.build(metadata: [("tokenizer.chat_template", .string(template))]))
        #expect((summary["chatTemplate"] as? String)?.contains("\u{200B}") == false)
        #expect(document.findings.map(\.kind) == [.hiddenZeroWidth])
    }

    @Test func hiddenCharactersInOtherShownStringsAreCounted() throws {
        let zero = "a\u{200B}b"
        let cases: [(String, [(String, GGUFFixtures.Value)])] = [
            ("name", [("general.name", .string(zero))]),
            ("author", [("general.author", .string(zero))]),
            ("other value", [("general.description", .string(zero))]),
            ("other key", [("general.\(zero)", .u32(1))]),
            ("base model", [("general.base_model.0.name", .string(zero))]),
            ("tag", [("general.tags", .strings(["fine", zero]))]),
            ("named template", [("tokenizer.chat_template.rag", .string(zero))])
        ]
        for (label, metadata) in cases {
            #expect(try findings(metadata: metadata) == [.hiddenZeroWidth: 1], "\(label)")
        }
        let tensors = [GGUFFixtures.Tensor(name: "blk.\(zero).weight", dimensions: [8], type: 0, offset: 0)]
        #expect(try kinds(GGUFFixtures.build(tensors: tensors)) == [.hiddenZeroWidth: 1])
    }

    @Test func ordinaryInternationalTextAndEmojiAreSilent() throws {
        let text = "日本語 café Türkçe हिन्दी 🙂 👨\u{200D}👩\u{200D}👧 ❤\u{FE0F}"
        let found = try findings(metadata: [
            ("general.name", .string(text)), ("tokenizer.chat_template", .string("{{ m }} " + text)),
            ("general.tags", .strings([text]))
        ])
        #expect(found.isEmpty)
    }

    @Test func vocabularyEntriesAndConcealedValuesAreNotScanned() throws {
        let found = try findings(metadata: [
            ("tokenizer.ggml.tokens", .strings(["a\u{200B}", "\u{202E}b", "c"])),
            ("general.api_key", .string("tok\u{200B}en"))
        ])
        #expect(found.isEmpty)
    }

    // MARK: Privacy

    private static let secret = "synthetic-secret-0123456789"

    @Test func aValueUnderASensitiveKeyIsConcealed() throws {
        let (_, document) = try GGUFTestSupport.parse(GGUFFixtures.build(metadata: [
            ("general.api_key", .string(Self.secret)), ("general.name", .string("Visible Name")),
            ("general.access_token", .string(Self.secret)), ("general.url", .string("https://example.test/model"))
        ]))
        let visible = PackageTestSupport.concealedText(document)
        #expect(!visible.contains(Self.secret))
        #expect(visible.contains("general.api_key") && visible.contains("Visible Name") && visible.contains("https://example.test/model"))
        #expect(document.sensitiveRanges.count >= 2)
        #expect(document.usesStructuredPrivacy)
    }

    @Test func aCredentialAssignmentInsideAnyShownStringIsConcealed() throws {
        let (_, document) = try GGUFTestSupport.parse(GGUFFixtures.build(metadata: [
            ("tokenizer.chat_template", .string("{{ m }} password = \(Self.secret)")),
            ("general.description", .string("api_key: \(Self.secret)")),
            ("general.author", .string("token=\(Self.secret)"))
        ]))
        #expect(!PackageTestSupport.concealedText(document).contains(Self.secret))
    }

    @Test func numbersUnderSensitiveKeysStayVisibleLikeEveryOtherSummary() throws {
        let (summary, _) = try GGUFTestSupport.parse(GGUFFixtures.build(metadata: [("tokenizer.ggml.bos_token_id", .u32(1))]))
        #expect((summary["otherMetadata"] as? [String: Int])?["tokenizer.ggml.bos_token_id"] == 1)
    }
}
