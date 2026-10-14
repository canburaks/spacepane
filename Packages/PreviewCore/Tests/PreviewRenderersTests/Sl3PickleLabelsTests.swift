import Foundation
import Testing
import PreviewContracts
import PreviewFormats
@testable import PreviewRenderers
@testable import PreviewFormats

// Decision 030: the labels of the pickle summary cover every field and enumerated value the scan writes.
// Wording lives in tools/localization/additions/sl3-pickle.json; these tests check only the structure.
@Suite("Pickle summary labels")
struct Sl3PickleLabelsTests {
    private let labels = SummaryLabelSet.pickle

    private func summary() throws -> [String: Any] {
        // Protocol 2: import os.system and collections.OrderedDict, then discard both.
        var bytes: [UInt8] = [0x80, 0x02]
        bytes += Array("cos\nsystem\n0ccollections\nOrderedDict\n0N.".utf8)
        let document = try PickleAdapter().parse(FileBytes(data: Data(bytes)), context: RequestContext(budget: .containerScan))
        return try #require(try JSONSerialization.jsonObject(with: Data(document.text.utf8)) as? [String: Any])
    }

    @Test func theSetOwnsOnlyTheFormatAndNamesEveryFieldTheScanWrites() throws {
        #expect(labels.formats == [.pickle])
        let json = try summary()
        let root = try #require(labels.fields([]))
        #expect(Set(json.keys).isSubset(of: root), "\(Set(json.keys).subtracting(root))")
        let element = try #require((json["imports"] as? [[String: Any]])?.first)
        let imports = try #require(labels.fields(["imports", "[]"]))
        #expect(Set(element.keys) == imports)
        #expect(labels.fields(["imports"]) == nil && labels.fields(["other"]) == nil)
    }

    @Test func everyListedFieldHasAKeyAndTheRightKindOfValue() throws {
        let fields = (labels.fields([]) ?? []).union(labels.fields(["imports", "[]"]) ?? [])
        #expect(Set(labels.keys.keys) == fields)
        #expect(labels.verbatimFields == ["container", "name"])
        #expect(labels.booleanFields == ["partial"])
        #expect(labels.countFields.isSubset(of: fields))
    }

    @Test func everyKindOfImportAndTheCheckedValueHaveALabel() throws {
        let kinds = Set(labels.valueLabels["kind"]?.keys.map { $0 } ?? [])
        #expect(kinds == Set(PickleImportKind.allCases.map(\.rawValue)))
        #expect(labels.valueLabels["checked"]?["importsOnly"] != nil)
        let json = try summary()
        #expect(json["checked"] as? String == "importsOnly")
    }
}
