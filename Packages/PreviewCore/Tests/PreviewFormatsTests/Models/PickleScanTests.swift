import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Pickle stream scan and summary")
struct PickleScanTests {
    private typealias S = PickleStream
    private let context = PackageTestSupport.context

    private func scan(_ bytes: [UInt8], isWindow: Bool = false, single: Bool = false, container: String = "Pickle",
                      budget: Int = PickleWalker.maximumOpcodes) throws -> (result: PickleStreamScanner.Result, report: PickleScanReport) {
        var report = PickleScanReport(container: container)
        report.opcodeBudget = budget
        let result = try PickleStreamScanner.scan(Data(bytes), isWindow: isWindow, single: single, report: &report, context: context)
        return (result, report)
    }

    @Test func legacyFilesHoldSeveralPicklesFollowedByRawData() throws {
        let storage = S.join([0x04, 0, 0, 0, 0, 0, 0, 0], [UInt8](repeating: 0x11, count: 16))
        let bytes = S.legacyFile(afterPickles: storage)
        #expect(PickleStreamScanner.isLegacyPyTorch(Data(bytes)))
        let (result, report) = try scan(bytes, isWindow: true)
        #expect(result == .scanned && report.pickles == 5 && report.persistentIDs == 1)
        #expect(!report.isBroken && !report.isPartial)
        #expect(report.tally.distinctCount(.expected) == 3 && report.tally.entries.count == 3)
    }

    @Test func rawDataThatLooksLikeAHeaderStopsTheScanQuietly() throws {
        let tail: [UInt8] = [0x80, 0x02, 0x7F, 0x7F, 0x7F, 0x80, 0x03]
        let (_, report) = try scan(S.legacyFile(afterPickles: tail))
        #expect(report.pickles == 5 && !report.isBroken && !report.isPartial)
        // The same bytes that name an import and then break are not quiet.
        let (_, loud) = try scan(S.legacyFile(afterPickles: S.join(S.proto2, S.global("os", "system"), [0x7F])))
        #expect(loud.pickles == 6 && loud.isBroken)
        #expect(loud.tally.distinctCount(.code) == 1)
    }

    @Test func atMostEightPicklesAreScannedAndTheRestMakeTheScanPartial() throws {
        let one = S.call("builtins", "set")
        let (_, nine) = try scan(Array((0..<9).map { _ in one }.joined()))
        #expect(nine.pickles == 8 && nine.isPartial)
        let (_, eight) = try scan(Array((0..<8).map { _ in one }.joined()))
        #expect(eight.pickles == 8 && !eight.isPartial)
    }

    @Test func aSingleScanIgnoresWhatFollowsTheFirstPickle() throws {
        let (_, report) = try scan(S.call("builtins", "set") + S.call("os", "system"), single: true)
        #expect(report.pickles == 1 && report.tally.distinctCount(.code) == 0)
    }

    @Test func headerlessPicklesAreAcceptedOnlyWhenTheyWalk() throws {
        let (complete, report) = try scan(S.textCall("os", "system"))
        #expect(complete == .scanned && report.pickles == 1 && report.protocolVersion == 0)
        // Text that is not a pickle, and a pickle that breaks before naming any import.
        #expect(try scan(Array("hello world\n".utf8)).result == .notAPickle)
        #expect(try scan(S.text("S'abc'\nXXXX")).result == .notAPickle)
        #expect(try scan(S.text("c a b\nname!\n")).result == .notAPickle)
        // A protocol 0 stream that names an import and then breaks keeps the shape of the attack.
        let (broken, loud) = try scan(Array(S.textCall("os", "system").dropLast()) + [0x7F])
        #expect(broken == .scanned && loud.isBroken && loud.tally.distinctCount(.code) == 1)
    }

    @Test func aHeaderedStreamThatBreaksWithoutImportsIsMalformed() {
        #expect(throws: PreviewFailure.malformedDocument) { try scan([0x80, 0x02, 0x7F]) }
        #expect(throws: PreviewFailure.malformedDocument) { try scan(S.join(S.proto2, S.none)) }
    }

    @Test func windowsAndCapsMakeTheScanPartialNotBroken() throws {
        let truncated = Array(S.call("os", "system").dropLast(8))
        let (_, window) = try scan(truncated, isWindow: true)
        #expect(window.isPartial && !window.isBroken && window.pickles == 1 && window.tally.distinctCount(.code) == 1)
        let (_, capped) = try scan(S.call("os", "system"), budget: 3)
        #expect(capped.isPartial && !capped.isBroken)
    }

    @Test func joblibArraysEndTheScanAsPartialBecauseRawBytesFollow() throws {
        let stream = S.join(S.proto2, S.global("joblib.numpy_pickle", "NumpyArrayWrapper"), [0x7F, 0x7F, 0x7F])
        let (_, report) = try scan(stream)
        #expect(report.isPartial && !report.isBroken)
        #expect(report.tally.distinctCount(.uncommon) == 1)
    }

    // MARK: Summary

    private func summary(_ report: PickleScanReport, scanned: Bool = true, mismatch: Bool = false) throws -> PickleResult {
        PickleResult(try PickleSummary.document(report, scanned: scanned, mismatch: mismatch, context: context))
    }

    @Test func theSummaryNamesWhatWasCheckedAndNeverCallsAFileSafe() throws {
        let (_, report) = try scan(S.torchCheckpoint(), container: "PyTorch ZIP")
        let result = try summary(report)
        #expect(result.json["checked"] as? String == "importsOnly")
        let text = result.document.text.lowercased()
        #expect(!text.contains("safe") && !text.contains("clean") && !text.contains("harmless"))
        #expect(result.document.findings.isEmpty)
    }

    @Test func importsBeyondTheListAreCountedAndMarkThePartialFlag() throws {
        var report = PickleScanReport(container: "Pickle")
        report.pickles = 1
        for index in 0..<300 { report.tally.record(module: "pkg\(index)", name: "Thing") }
        let result = try summary(report)
        #expect(result.imports.count == PickleSummary.maximumListedImports)
        #expect(result.json["partial"] as? Bool == true)
        #expect(result.count(of: .pickleUncommonImports) == 300)
    }

    @Test func aFileOfAnotherKindGetsOnlyItsContainerAndTheMismatch() throws {
        let result = try summary(PickleScanReport(container: "7z"), scanned: false, mismatch: true)
        #expect(result.container == "7z" && result.json.keys.sorted() == ["container"])
        #expect(result.findings == [.artifactMismatchedContent])
    }

    @Test func importNamesTheReaderSeesAreConcealedWhenTheyLookLikeCredentialAssignments() throws {
        var report = PickleScanReport(container: "Pickle")
        report.pickles = 1
        report.tally.record(module: "api_key=hunter2hunter2", name: "Thing")
        let result = try summary(report)
        #expect(!PackageTestSupport.concealedText(result.document).contains("hunter2"))
    }
}
