import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Safetensors findings and privacy")
struct SafetensorsFindingsTests {
    private typealias Tensor = SafetensorsFixtures.Tensor

    private func tensor(_ name: String, _ dtype: String = "U8", _ shape: [UInt64] = [4], _ begin: UInt64, _ end: UInt64) -> Tensor {
        Tensor(name: name, dtype: dtype, shape: shape, begin: begin, end: end)
    }

    private func findings(_ tensors: [Tensor], dataBytes: Int? = nil, metadata: [(String, String)]? = nil) throws -> [PreviewFindingKind: Int] {
        try SafetensorsTestSupport.findings(SafetensorsFixtures.file(tensors, metadata: metadata, dataBytes: dataBytes))
    }

    // MARK: Incomplete files

    @Test func dataCutShortIsReportedWithTheNumberOfTensorsBeyondTheFile() throws {
        let tensors = SafetensorsFixtures.laidOut([("a", "F32", [4]), ("b", "F32", [4]), ("c", "F32", [4])])
        #expect(try findings(tensors).isEmpty)
        #expect(try findings(tensors, dataBytes: 47) == [.modelIncomplete: 1])
        #expect(try findings(tensors, dataBytes: 20) == [.modelIncomplete: 2])
        #expect(try findings(tensors, dataBytes: 0) == [.modelIncomplete: 3])
    }

    @Test func theFindingsCarryNoLinesAndNoDetail() throws {
        let data = SafetensorsFixtures.file(SafetensorsFixtures.laidOut([("a", "F32", [4])]), dataBytes: 0)
        let (_, document) = try SafetensorsTestSupport.parse(data)
        let finding = try #require(document.findings.first)
        #expect(finding.lines.isEmpty && finding.detail == .none && finding.severity == .caution)
    }

    // MARK: Layout

    @Test func overlapsAndHolesAreInconsistent() throws {
        #expect(try findings([tensor("a", "U8", [4], 0, 4), tensor("b", "U8", [4], 2, 6)]) == [.modelInconsistentLayout: 1])
        #expect(try findings([tensor("a", "U8", [4], 0, 4), tensor("b", "U8", [4], 0, 4)]) == [.modelInconsistentLayout: 1])
        #expect(try findings([tensor("a", "U8", [4], 0, 4), tensor("b", "U8", [4], 6, 10)]) == [.modelInconsistentLayout: 1])
        #expect(try findings([tensor("a", "U8", [4], 2, 6)]) == [.modelInconsistentLayout: 1], "the first range must start at zero")
    }

    @Test func tensorsInAnyOrderInTheHeaderAreFineWhenTheRangesTile() throws {
        let tiled = [tensor("b", "U8", [4], 4, 8), tensor("a", "U8", [4], 0, 4), tensor("c", "U8", [0], 8, 8)]
        #expect(try findings(tiled).isEmpty)
    }

    @Test func aSizeThatDisagreesWithDtypeAndShapeIsInconsistent() throws {
        #expect(try findings([tensor("a", "F32", [4], 0, 8)], dataBytes: 8) == [.modelInconsistentLayout: 1])
        #expect(try findings([tensor("a", "U8", [4], 0, 3)], dataBytes: 3) == [.modelInconsistentLayout: 1])
        #expect(try findings([tensor("a", "F4", [3], 0, 2)], dataBytes: 2) == [.modelInconsistentLayout: 1], "12 bits is not whole bytes")
        #expect(try findings([tensor("a", "F4", [4], 0, 2)], dataBytes: 2).isEmpty)
        #expect(try findings([tensor("a", "F6_E2M3", [4], 0, 3)], dataBytes: 3).isEmpty)
    }

    @Test func bytesAfterTheLastTensorAreAHole() throws {
        let tensors = SafetensorsFixtures.laidOut([("a", "F32", [4])])
        #expect(try findings(tensors, dataBytes: 17) == [.modelInconsistentLayout: 1])
        #expect(try findings(tensors, dataBytes: 16).isEmpty)
    }

    @Test func everyKnownDtypeSizeMatchesTheIndependentFixtureTable() throws {
        let dtypes = ["F32", "I32", "U32", "F16", "BF16", "I16", "U16", "I8", "U8", "BOOL", "F8_E4M3", "F8_E5M2", "F64", "I64", "U64"]
        let tensors = SafetensorsFixtures.laidOut(dtypes.map { ("t.\($0)", $0, [UInt64(3), 5]) })
        #expect(try findings(tensors).isEmpty)
    }

    // MARK: Hidden characters

    @Test func hiddenCharactersInMetadataAndNamesGiveFindings() throws {
        let one = [tensor("a", "U8", [4], 0, 4)]
        let zero = "a\u{200B}\u{200B}b"
        #expect(try findings(one, metadata: [("note", zero)]) == [.hiddenZeroWidth: 2])
        #expect(try findings(one, metadata: [("not\u{200B}e", "plain")]) == [.hiddenZeroWidth: 1])
        #expect(try findings([tensor("blk.\u{202E}.w", "U8", [4], 0, 4)]) == [.hiddenBidirectionalControls: 1])
        #expect(try findings([tensor("w", "U\u{200B}8", [4], 0, 4)], dataBytes: 4) == [.hiddenZeroWidth: 1],
                "an unknown dtype name is shown in the dtype table and the tensor list, and counted once")
        #expect(try findings(one, metadata: [("tags", "x\u{E0041}\u{E0042}y"), ("note", "p\u{E000}q")]) == [.hiddenUnicodeTags: 2, .hiddenPrivateUse: 1])
    }

    @Test func escapedHiddenCharactersAreDecodedBeforeTheyAreCounted() throws {
        let json = "{\"__metadata__\":{\"note\":\"a\\u202eb\\u200bc\"}}"
        let (_, document) = try SafetensorsTestSupport.parse(SafetensorsFixtures.file(json: json))
        #expect(Set(document.findings.map(\.kind)) == [.hiddenBidirectionalControls, .hiddenZeroWidth])
        for finding in document.findings { #expect(finding.lines.isEmpty && finding.detail == .none) }
    }

    @Test func ordinaryInternationalTextIsSilent() throws {
        let text = "日本語 café Türkçe हिन्दी 🙂 👨\u{200D}👩\u{200D}👧 ❤\u{FE0F}"
        let one = [tensor("a", "U8", [4], 0, 4)]
        #expect(try findings(one, metadata: [("description", text), ("format", "pt")]).isEmpty)
    }

    @Test func concealedValuesAreNotScannedForHiddenCharacters() throws {
        let one = [tensor("a", "U8", [4], 0, 4)]
        #expect(try findings(one, metadata: [("api_key", "tok\u{200B}en")]).isEmpty)
    }

    // MARK: Privacy

    private static let secret = "synthetic-secret-0123456789"

    @Test func aMetadataValueUnderASensitiveKeyIsConcealed() throws {
        let data = SafetensorsFixtures.file([], metadata: [
            ("api_key", Self.secret), ("hf_token", Self.secret), ("author", "Visible Author"), ("source", "https://example.test/model")
        ])
        let (_, document) = try SafetensorsTestSupport.parse(data)
        let visible = PackageTestSupport.concealedText(document)
        #expect(!visible.contains(Self.secret))
        #expect(visible.contains("api_key") && visible.contains("Visible Author") && visible.contains("https://example.test/model"))
        #expect(document.sensitiveRanges.count >= 2 && document.usesStructuredPrivacy)
    }

    @Test func aCredentialAssignmentInsideAnyShownValueIsConcealed() throws {
        let data = SafetensorsFixtures.file([], metadata: [("description", "password = \(Self.secret)"), ("notes", "token: \(Self.secret)")])
        let (_, document) = try SafetensorsTestSupport.parse(data)
        #expect(!PackageTestSupport.concealedText(document).contains(Self.secret))
    }

    @Test func aLongTrainingMetadataValueIsClippedAndStillConcealedWhenSensitive() throws {
        let long = String(repeating: "word ", count: 2_000)
        let data = SafetensorsFixtures.file([], metadata: [("ss_tag_frequency", long), ("secret_note", long)])
        let (summary, document) = try SafetensorsTestSupport.parse(data)
        let shown = summary["metadata"] as? [String: String] ?? [:]
        #expect(shown.values.allSatisfy { $0.utf8.count <= PackageSummary.maximumTextBytes })
        #expect(!PackageTestSupport.concealedText(document).contains("secret_note\": \"word"))
    }
}
