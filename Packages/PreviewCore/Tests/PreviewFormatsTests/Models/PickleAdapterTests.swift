import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Pickle adapter routes")
struct PickleAdapterTests {
    private typealias S = PickleStream

    /// The registered budget (16 MiB of reads), with a deadline that a loaded test run will not trip.
    private func context(file: String, input: Int = 16_777_216) -> RequestContext {
        var context = RequestContext(budget: PreviewBudget(maxInputBytes: input, maxMilliseconds: 30_000))
        context.nameHint = PreviewNameHint(filename: file, suffix: (file as NSString).pathExtension)
        return context
    }

    private func document(_ data: Data, file: String = "model.pt", input: Int = 16_777_216) throws -> ParsedTextDocument {
        try PickleAdapter().parse(DataByteSource(data), context: context(file: file, input: input))
    }

    private func scan(_ bytes: [UInt8], file: String = "model.pt") throws -> PickleResult {
        PickleResult(try document(Data(bytes), file: file))
    }

    // MARK: Raw pickles

    @Test func aRawPickleIsScannedWhateverItsSuffix() throws {
        for file in ["a.pt", "a.pth", "a.ckpt", "a.pickle", "a.joblib", "noextension"] {
            let result = try scan(S.call("os", "system"), file: file)
            #expect(result.container == "Pickle" && result.kind(of: "os.system") == "code", "\(file)")
            #expect(result.findings == [.pickleRunsCode], "\(file)")
        }
    }

    @Test func protocolZeroTextIsScannedNotShownAsText() throws {
        let result = try scan(S.textCall("os", "system"), file: "evil.pickle")
        #expect(result.container == "Pickle" && result.protocolVersion == 0)
        #expect(result.kind(of: "os.system") == "code")
    }

    @Test func legacyTorchFilesAreRecognizedByTheirMagicNumber() throws {
        let storage = S.join([0x04, 0, 0, 0, 0, 0, 0, 0], [UInt8](repeating: 0x11, count: 16))
        let result = try scan(S.legacyFile(afterPickles: storage))
        #expect(result.container == "PyTorch legacy" && result.json["pickles"] as? Int == 5)
        #expect(result.document.findings.isEmpty && result.json["partial"] as? Bool == false)
        #expect(result.json["storages"] == nil)
    }

    @Test func aBigFileIsReadOnlyAsFarAsItsFirstPicklesGo() throws {
        let big = Data(S.legacyFile(afterPickles: [])) + Data(count: 9 * 1_048_576)
        let result = PickleResult(try document(big))
        #expect(result.json["pickles"] as? Int == 5 && result.json["partial"] as? Bool == false)
        // A pickle that runs past the window is partial, not broken.
        let long = S.join(S.proto2, [0x8D], S.littleEndian(9 * 1_048_576, width: 8), [UInt8](repeating: 0x61, count: 9 * 1_048_576))
        let partial = PickleResult(try document(Data(long)))
        #expect(partial.json["partial"] as? Bool == true && partial.findings.isEmpty)
    }

    @Test func importsBeforeAnInvalidOpcodeAreReportedWithTheBrokenStream() throws {
        let result = try scan(Array(S.call("subprocess", "Popen").dropLast()) + [0x7F])
        #expect(result.findings == [.pickleRunsCode, .pickleBrokenStream])
    }

    @Test func whatIsNotAPickleIsNotSummarizedAsOne() {
        let samples: [(String, [UInt8])] = [
            ("text", Array("hello world\n".utf8)), ("path text", Array("/usr/lib/python\n/opt/lib\n".utf8)),
            ("binary junk", [0x00, 0x01, 0x02, 0xFE, 0xFF, 0x10]), ("jpeg", [0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10])
        ]
        for (name, bytes) in samples {
            for file in ["a.pt", "a.pickle", "a.ckpt", "a.joblib"] {
                #expect(throws: PreviewFailure.unsupportedFormat, "\(name) as \(file)") { try scan(bytes, file: file) }
            }
        }
        #expect(throws: PreviewFailure.malformedDocument) { try scan([]) }
        #expect(throws: PreviewFailure.malformedDocument) { try scan([0x80, 0x02]) }
    }

    @Test func theFileBytesRouteGivesTheSameSummary() throws {
        let data = Data(S.call("os", "system"))
        let viaSource = try document(data)
        let viaBytes = try PickleAdapter().parse(FileBytes(data: data), context: context(file: "model.pt"))
        #expect(viaBytes.text == viaSource.text && viaBytes.findings == viaSource.findings)
    }

    @Test func scanningARawPickleStopsWhenCancelled() async throws {
        let pair: [UInt8] = [0x4E, 0x30]
        let pickle = S.join(S.proto2, Array((0..<40_000).map { _ in pair }.joined()), S.none, S.stop)
        let document = try await CancellationTest.expectStopsActiveParse(budget: .containerScan) { context in
            try PickleAdapter().parse(DataByteSource(Data(pickle)), context: context)
        }
        #expect(document.origin == .summary)
    }

    // MARK: Compressed pickles

    private var joblibStream: [UInt8] {
        S.join(S.proto2, S.global("sklearn.tree._classes", "DecisionTreeClassifier"), S.pop, S.global("joblib.numpy_pickle", "NumpyArrayWrapper"),
               S.pop, S.none, S.stop)
    }

    @Test(arguments: [(Int32(15), "zlib"), (Int32(31), "gzip")])
    func joblibFilesCompressedWithZlibOrGzipAreScanned(windowBits: Int32, name: String) throws {
        let packed = PyTorchZip.compress(Data(joblibStream), windowBits: windowBits)
        let result = PickleResult(try document(packed, file: "model.joblib"))
        #expect(result.container == "joblib (\(name))")
        #expect(result.importNames == ["joblib.numpy_pickle.NumpyArrayWrapper", "sklearn.tree._classes.DecisionTreeClassifier"])
        #expect(result.findings == [.pickleUncommonImports])
    }

    @Test func compressedMaliciousImportsAreFoundToo() throws {
        let packed = PyTorchZip.compress(Data(S.call("os", "system")), windowBits: 15)
        #expect(try PickleResult(document(packed, file: "model.pt")).findings == [.pickleRunsCode])
    }

    @Test func aBzip2OrXzMagicRoutesToTheirDecodersWhichRejectBadStreams() {
        for header in [Array("BZh9".utf8) + [UInt8](repeating: 0x41, count: 40), [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00] + [UInt8](repeating: 0, count: 40)] {
            #expect(throws: PreviewFailure.self) { try scan(header) }
        }
    }

    @Test func compressionWithoutADecoderIsAnUnsupportedVariant() {
        for header: [UInt8] in [[0x28, 0xB5, 0x2F, 0xFD, 0, 0, 0, 0], [0x04, 0x22, 0x4D, 0x18, 0, 0, 0, 0], [0x5D, 0, 0, 0x80, 0, 0, 0, 0]] {
            #expect(throws: PreviewFailure.unsupportedVariant) { try scan(header) }
        }
    }

    @Test func decompressionIsBounded() {
        let bomb = PyTorchZip.compress(Data(count: PickleAdapter.maximumDecodedBytes + 1_048_576), windowBits: 15)
        #expect(throws: PreviewFailure.outputTooLarge) { try document(bomb) }
        let tooBigToRead = PyTorchZip.compress(Data(S.call("os", "system")), windowBits: 15)
        #expect(throws: PreviewFailure.inputTooLarge) { try document(tooBigToRead, input: tooBigToRead.count + 10) }
    }

    @Test func compressedDataThatIsNotAPickleIsRejected() {
        let text = PyTorchZip.compress(Data("just some text, no pickle here\n".utf8), windowBits: 15)
        #expect(throws: PreviewFailure.unsupportedFormat) { try document(text) }
    }

    @Test func aTextPickleThatOnlyLooksLikeAZlibHeaderIsNotTreatedAsOne() throws {
        // "(S" has a valid zlib header check but is the start of a perfectly ordinary protocol 0 pickle.
        let result = try scan(S.text("(S'a'\nS'b'\ntp0\n."), file: "t.pickle")
        #expect(result.container == "Pickle")
    }

    // MARK: Other kinds of file

    @Test func filesOfAnotherKindAreNamedAndFlaggedAndNotOpened() throws {
        let safetensors = S.join(S.littleEndian(2, width: 8), Array("{}".utf8), [UInt8](repeating: 0, count: 8))
        let samples: [(String, [UInt8])] = [
            ("7z", [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00, 0x04] + [UInt8](repeating: 0, count: 32)),
            ("GGUF", Array("GGUF".utf8) + [3, 0, 0, 0] + [UInt8](repeating: 0, count: 16)),
            ("safetensors", safetensors), ("HDF5", [0x89, 0x48, 0x44, 0x46, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]),
            ("NumPy", [0x93] + Array("NUMPY".utf8) + [1, 0, 0x76, 0])
        ]
        for (container, bytes) in samples {
            for file in ["model.pt", "model.ckpt", "model.pth"] {
                let result = try scan(bytes, file: file)
                #expect(result.container == container, "\(container) as \(file)")
                #expect(result.findings == [.artifactMismatchedContent], "\(container) as \(file)")
                #expect(result.json.keys.sorted() == ["container"], "\(container) as \(file)")
            }
        }
    }

    @Test func aSafetensorsLookalikeNeedsAPlausibleHeader() {
        // A length beyond the file, or a header that does not open with a brace, is not safetensors.
        #expect(PickleSniffer.kind(of: Data(S.join(S.littleEndian(5_000, width: 8), Array("{}".utf8))), size: 20) == .other)
        #expect(PickleSniffer.kind(of: Data(S.join(S.littleEndian(2, width: 8), Array("[]".utf8))), size: 20) == .other)
    }

    // MARK: Python path files

    @Test func aPathFileIsShownAsTextWithItsOwnCharacters() throws {
        let text = "# site additions\n/opt/lib/python3/site-packages\nimport sys; sys.path.append('/x')\n/opt/ünïcode\n"
        let parsed = try document(Data(text.utf8), file: "extra.pth")
        #expect(parsed.text == text && parsed.origin == .source && parsed.decodedEncoding == .utf8)
        #expect(parsed.findings.isEmpty && parsed.sensitiveRanges.isEmpty)
    }

    @Test func aByteOrderMarkIsNotPartOfTheText() throws {
        let parsed = try document(Data([0xEF, 0xBB, 0xBF] + Array("/opt/lib\n".utf8)), file: "extra.pth")
        #expect(parsed.text == "/opt/lib\n")
    }

    @Test func theSuffixIsComparedWithoutCase() throws {
        #expect(try document(Data("/opt/lib\n".utf8), file: "SITE.PTH").origin == .source)
    }

    @Test func textUnderAnyOtherNameIsNotAPathFile() {
        for file in ["a.pt", "a.ckpt", "a.pickle", "a.joblib", "pth", "a.pth.txt"] {
            #expect(throws: PreviewFailure.unsupportedFormat, "\(file)") { try document(Data("/opt/lib\n".utf8), file: file) }
        }
    }

    @Test func aPathFileAboveTheTextLimitOrWithNulBytesIsNotShown() {
        let large = Data(repeating: 0x61, count: PickleAdapter.maximumTextBytes + 1)
        #expect(throws: PreviewFailure.unsupportedFormat) { try document(large, file: "big.pth") }
        #expect(throws: PreviewFailure.unsupportedFormat) { try document(Data([0x2F, 0x6F, 0x00, 0x70, 0x0A]), file: "nul.pth") }
    }

    @Test func aPickleSavedUnderAPathFileNameIsStillScanned() throws {
        for bytes in [S.call("os", "system"), S.textCall("os", "system")] {
            let result = try scan(bytes, file: "weights.pth")
            #expect(result.container == "Pickle" && result.findings == [.pickleRunsCode])
        }
        // A path file whose first line happens to open like a pickle opcode stays text.
        let parsed = try document(Data("cache/lib\nother\n".utf8), file: "odd.pth")
        #expect(parsed.origin == .source)
    }
}
