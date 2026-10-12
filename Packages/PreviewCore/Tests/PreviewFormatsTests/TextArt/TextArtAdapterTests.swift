import Foundation
import Testing
import PreviewContracts
import PreviewFormats

private func parseArt(_ bytes: [UInt8], budget: PreviewBudget = .standard) throws -> ParsedTextDocument {
    try TextArtAdapter().parse(FileBytes(data: Data(bytes)), context: RequestContext(budget: budget))
}

private func scalars(_ text: String) -> [UInt32] { text.unicodeScalars.map(\.value) }

/// Microsoft's CP437.TXT 0x80...0xFF column as 16-scalar rows, spelled independently of the
/// production table so a wrong production entry fails here.
private let publishedUpperHalf: [String] = [
    "\u{00C7}\u{00FC}\u{00E9}\u{00E2}\u{00E4}\u{00E0}\u{00E5}\u{00E7}\u{00EA}\u{00EB}\u{00E8}\u{00EF}\u{00EE}\u{00EC}\u{00C4}\u{00C5}",
    "\u{00C9}\u{00E6}\u{00C6}\u{00F4}\u{00F6}\u{00F2}\u{00FB}\u{00F9}\u{00FF}\u{00D6}\u{00DC}\u{00A2}\u{00A3}\u{00A5}\u{20A7}\u{0192}",
    "\u{00E1}\u{00ED}\u{00F3}\u{00FA}\u{00F1}\u{00D1}\u{00AA}\u{00BA}\u{00BF}\u{2310}\u{00AC}\u{00BD}\u{00BC}\u{00A1}\u{00AB}\u{00BB}",
    "\u{2591}\u{2592}\u{2593}\u{2502}\u{2524}\u{2561}\u{2562}\u{2556}\u{2555}\u{2563}\u{2551}\u{2557}\u{255D}\u{255C}\u{255B}\u{2510}",
    "\u{2514}\u{2534}\u{252C}\u{251C}\u{2500}\u{253C}\u{255E}\u{255F}\u{255A}\u{2554}\u{2569}\u{2566}\u{2560}\u{2550}\u{256C}\u{2567}",
    "\u{2568}\u{2564}\u{2565}\u{2559}\u{2558}\u{2552}\u{2553}\u{256B}\u{256A}\u{2518}\u{250C}\u{2588}\u{2584}\u{258C}\u{2590}\u{2580}",
    "\u{03B1}\u{00DF}\u{0393}\u{03C0}\u{03A3}\u{03C3}\u{00B5}\u{03C4}\u{03A6}\u{0398}\u{03A9}\u{03B4}\u{221E}\u{03C6}\u{03B5}\u{2229}",
    "\u{2261}\u{00B1}\u{2265}\u{2264}\u{2320}\u{2321}\u{00F7}\u{2248}\u{00B0}\u{2219}\u{00B7}\u{221A}\u{207F}\u{00B2}\u{25A0}\u{00A0}"
]

@Suite("Text-art adapter")
struct TextArtAdapterTests {
    @Test func boxDrawingDecodesFromCodePage437WithExactCRLFAndProvenance() throws {
        let bytes: [UInt8] = [0xC9, 0xCD, 0xCD, 0xCD, 0xBB, 0x0D, 0x0A, 0xBA, 0x20, 0x41, 0x72, 0x74, 0x20, 0xBA, 0x0D, 0x0A,
                              0xC8, 0xCD, 0xCD, 0xCD, 0xBC, 0x0D, 0x0A]
        let parsed = try parseArt(bytes)
        let expected = "\u{2554}\u{2550}\u{2550}\u{2550}\u{2557}\r\n\u{2551} Art \u{2551}\r\n\u{255A}\u{2550}\u{2550}\u{2550}\u{255D}\r\n"
        #expect(scalars(parsed.text) == scalars(expected))
        #expect(parsed.decodedEncoding == .codePage437)
        #expect(parsed.syntax == .plain)
        #expect(parsed.usesStructuredPrivacy == false)
        #expect(parsed.sensitiveRanges.isEmpty)
    }

    @Test func everyUpperHalfByteMatchesThePublishedTable() throws {
        let expected = publishedUpperHalf.joined()
        #expect(expected.unicodeScalars.count == 128)
        let parsed = try parseArt(Array(0x80...0xFF))
        #expect(scalars(parsed.text) == scalars(expected))
        #expect(parsed.decodedEncoding == .codePage437)
        // Every byte also decodes alone, so no entry depends on its neighbours.
        for (offset, scalar) in expected.unicodeScalars.enumerated() {
            let single = try parseArt([UInt8(0x80 + offset)])
            #expect(scalars(single.text) == [scalar.value], "byte \(0x80 + offset)")
        }
    }

    @Test func documentedSpotChecksAndAgreementWithTheSystemCodec() throws {
        let spots: [(UInt8, UInt32)] = [(0x80, 0xC7), (0x81, 0xFC), (0x9E, 0x20A7), (0x9F, 0x192), (0xA8, 0xBF), (0xB0, 0x2591),
                                        (0xB3, 0x2502), (0xC4, 0x2500), (0xCD, 0x2550), (0xDB, 0x2588), (0xE1, 0xDF), (0xE6, 0xB5),
                                        (0xF8, 0xB0), (0xF9, 0x2219), (0xFA, 0xB7), (0xFE, 0x25A0), (0xFF, 0xA0)]
        for (byte, value) in spots {
            #expect(scalars(try parseArt([byte]).text) == [value], "byte \(byte)")
        }
        // Apple's IBM437 table is an independent oracle for the same 128 entries.
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)))
        let system = String(data: Data(0x80...0xFF), encoding: encoding)
        #expect(system != nil)
        if let system {
            let ours = scalars(publishedUpperHalf.joined())
            let theirs = scalars(system)
            #expect(theirs.count == 128)
            let differences = zip(ours, theirs).enumerated().filter { $0.element.0 != $0.element.1 }.map { 0x80 + $0.offset }
            #expect(differences.isEmpty, "System IBM437 differs at bytes \(differences)")
        }
    }

    @Test func asciiControlsKeepTabAndLineBreaksAndNeverNormalizeThem() throws {
        let parsed = try parseArt(Array("a\tb\r\nc\rd\ne".utf8))
        #expect(parsed.text.utf8.elementsEqual("a\tb\r\nc\rd\ne".utf8))
        #expect(parsed.decodedEncoding == .utf8)
    }

    @Test(arguments: [0x00, 0x01, 0x07, 0x08, 0x0B, 0x0C, 0x0E, 0x19, 0x1B, 0x1F, 0x7F] as [UInt8])
    func binaryControlBytesAreRejectedInEitherEncoding(control: UInt8) {
        #expect(throws: PreviewFailure.binaryContent) { try parseArt([0x61, control, 0x62]) }
        #expect(throws: PreviewFailure.binaryContent) { try parseArt([0xC9, control, 0xBB]) }
        #expect(throws: PreviewFailure.binaryContent) { try parseArt([control]) }
    }

    @Test func utf16AndOtherNULBearingInputsAreBinary() {
        #expect(throws: PreviewFailure.binaryContent) { try parseArt([0xFF, 0xFE, 0x41, 0x00, 0x42, 0x00]) }
        #expect(throws: PreviewFailure.binaryContent) { try parseArt([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00]) }
    }

    @Test func trailingCtrlZEndOfFileMarkersAreDroppedButInteriorOnesAreBinary() throws {
        #expect(scalars(try parseArt([0xC9, 0x0D, 0x0A, 0x1A]).text) == [0x2554, 0x0D, 0x0A])
        #expect(try parseArt(Array("plain\n".utf8) + [0x1A, 0x1A, 0x1A]).text == "plain\n")
        #expect(try parseArt([0x1A]).text == "")
        #expect(throws: PreviewFailure.binaryContent) { try parseArt([0x61, 0x1A, 0x62]) }
        #expect(throws: PreviewFailure.binaryContent) { try parseArt([0x61, 0x1A, 0x0A, 0x1A]) }
    }

    @Test func validUTF8DecodesAsUTF8IncludingBoxDrawingAndDropsOneBOM() throws {
        let source = "Caf\u{E9} \u{2554}\u{2550}\u{2557} \u{65E5}\u{672C}\u{8A9E} \u{1F600}\r\n"
        let plain = try parseArt(Array(source.utf8))
        #expect(plain.text.utf8.elementsEqual(source.utf8))
        #expect(plain.decodedEncoding == .utf8)
        let withBOM = try parseArt([0xEF, 0xBB, 0xBF] + Array(source.utf8))
        #expect(withBOM.text.utf8.elementsEqual(source.utf8))
        #expect(withBOM.decodedEncoding == .utf8)
        #expect(scalars(try parseArt([0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF, 0x61]).text) == [0xFEFF, 0x61])
        #expect(try parseArt([]).text == "")
        #expect(try parseArt([0xEF, 0xBB, 0xBF]).text == "")
    }

    @Test func invalidUTF8FallsBackToCodePage437IncludingAnyBOMLikeBytes() throws {
        // A lone lead byte is not UTF-8, so the whole file is CP437 and nothing is dropped.
        #expect(scalars(try parseArt([0x41, 0xC9]).text) == [0x41, 0x2554])
        #expect(scalars(try parseArt([0xEF, 0xBB, 0xBF, 0xC9]).text) == [0x2229, 0x2557, 0x2510, 0x2554])
        // Bytes that happen to form valid UTF-8 are UTF-8; this is the documented preference.
        let accidental = try parseArt([0xC4, 0xB0])
        #expect(scalars(accidental.text) == [0x130])
        #expect(accidental.decodedEncoding == .utf8)
        // Real box drawing almost always breaks UTF-8 validity with repeated lead bytes.
        #expect(try parseArt([0xC4, 0xC4, 0xB0]).decodedEncoding == .codePage437)
    }

    @Test func assignmentLinesStayPlainTextForTheSharedHeuristic() throws {
        let parsed = try parseArt([0xBA, 0x20] + Array("password=synthetic-secret\r\n".utf8))
        #expect(parsed.text.utf8.elementsEqual("\u{2551} password=synthetic-secret\r\n".utf8))
        #expect(parsed.usesStructuredPrivacy == false)
    }

    @Test func inputOutputLineAndLengthLimits() {
        #expect(throws: PreviewFailure.inputTooLarge) { try parseArt([0x61, 0x62, 0x63, 0x64, 0x65], budget: PreviewBudget(maxInputBytes: 4)) }
        // Each 0xDB byte decodes to three UTF-8 bytes, so the output cap trips before the input cap.
        let blocks = [UInt8](repeating: 0xDB, count: 400)
        #expect(throws: PreviewFailure.outputTooLarge) { try parseArt(blocks, budget: PreviewBudget(maxOutputUTF8Bytes: 1_000)) }
        #expect(throws: PreviewFailure.outputTooLarge) {
            try parseArt(Array("abcdef".utf8), budget: PreviewBudget(maxOutputUTF8Bytes: 5))
        }
        #expect(throws: PreviewFailure.tooManyLines) { try parseArt(Array("a\nb\nc".utf8), budget: PreviewBudget(maxTextLines: 2)) }
        #expect(throws: PreviewFailure.tooManyLines) { try parseArt([0xC9, 0x0D, 0xC9, 0x0D, 0xC9], budget: PreviewBudget(maxTextLines: 2)) }
        // CRLF counts once, matching the shared text limits.
        #expect((try? parseArt(Array("a\r\nb".utf8), budget: PreviewBudget(maxTextLines: 2))) != nil)
        // Line length is measured on decoded UTF-8: two box characters are six bytes.
        #expect(throws: PreviewFailure.lineTooLong) { try parseArt([0xC9, 0xCD], budget: PreviewBudget(maxLineUTF8Bytes: 5)) }
        #expect((try? parseArt([0xC9, 0xCD], budget: PreviewBudget(maxLineUTF8Bytes: 6))) != nil)
    }

    @Test func preCancelledRequestsStopBeforeScanning() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try parseArt([0xC9]); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        #expect(await task.value)
    }

    @Test func expiredDeadlineStopsLargeInputs() {
        let bytes = [UInt8](repeating: 0xB0, count: 8_000_000)
        let budget = PreviewBudget(maxInputBytes: 16_777_216, maxOutputUTF8Bytes: 33_554_432, maxMilliseconds: 1)
        #expect(throws: PreviewFailure.deadlineExceeded) { try parseArt(bytes, budget: budget) }
    }

    @Test func cooperativeCancellationStopsAnActiveLargeInput() async throws {
        // Code page 437 shade rows within the line budgets, so only cancellation can stop the parse.
        let row = [UInt8](repeating: 0xB0, count: 79) + [13, 10]
        let bytes = FileBytes(data: Data(Array(repeating: row, count: 13_000).joined()))
        let budget = PreviewBudget(maxInputBytes: 16_777_216, maxOutputUTF8Bytes: 33_554_432, maxTextLines: 100_000,
                                   maxMilliseconds: 30_000)
        let completed = try await CancellationTest.expectStopsActiveParse(budget: budget) {
            try TextArtAdapter().parse(bytes, context: $0)
        }
        #expect(completed.decodedEncoding == .codePage437)
    }
}
