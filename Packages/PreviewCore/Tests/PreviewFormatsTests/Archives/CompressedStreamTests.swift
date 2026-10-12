import Compression
import Foundation
import zlib
import Testing
import PreviewContracts
@testable import PreviewFormats

private let streamContext = RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000))
private let samplePaths = ["Example/", "Example/readme.txt", "Example/data/values.json", "Example/notes.md"]

private func gzip(_ data: Data) throws -> Data {
    var stream = z_stream()
    guard deflateInit2_(&stream, 6, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
        throw PreviewFailure.unavailableContent
    }
    defer { deflateEnd(&stream) }
    var output = Data(count: data.count + 128)
    let capacity = output.count
    return try data.withUnsafeBytes { input in
        try output.withUnsafeMutableBytes { target in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress!)
            stream.avail_in = uInt(data.count)
            stream.next_out = target.bindMemory(to: UInt8.self).baseAddress!
            stream.avail_out = uInt(capacity)
            guard deflate(&stream, Z_FINISH) == Z_STREAM_END else { throw PreviewFailure.malformedDocument }
            return Data(target.prefix(capacity - Int(stream.avail_out)))
        }
    }
}

private func xzStream(_ data: Data) -> Data {
    var output = [UInt8](repeating: 0, count: max(512, data.count * 2 + 128))
    let capacity = output.count
    let count = data.withUnsafeBytes { input in
        output.withUnsafeMutableBufferPointer { target in
            compression_encode_buffer(target.baseAddress!, capacity, input.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_LZMA)
        }
    }
    return Data(output.prefix(count))
}

/// A USTAR header; `mtime` is the raw 12-byte field so tests can store blanks or odd values.
private func tarEntry(path: String, mtime: [UInt8], payload: String = "x") -> Data {
    var header = [UInt8](repeating: 0, count: 512)
    func put(_ bytes: [UInt8], at offset: Int) { for (index, byte) in bytes.enumerated() { header[offset + index] = byte } }
    put(Array(path.utf8), at: 0)
    put(Array("0000644\0".utf8), at: 100)
    put(Array((String(format: "%011o", payload.utf8.count) + "\0").utf8), at: 124)
    put(mtime, at: 136)
    header[156] = 48
    put(Array("ustar\0".utf8), at: 257)
    for index in 148..<156 { header[index] = 32 }
    put(Array((String(format: "%06o", header.reduce(0) { $0 + Int($1) }) + "\0 ").utf8), at: 148)
    let body = Array(payload.utf8)
    return Data(header + body + [UInt8](repeating: 0, count: (512 - body.count % 512) % 512))
}
private func tarArchive(_ entries: [Data]) -> Data { entries.reduce(Data(), +) + Data(repeating: 0, count: 1024) }
private func octal(_ value: Int) -> [UInt8] { Array((String(format: "%011o", value) + "\0").utf8) }

@Suite("bzip2 and xz streams")
struct CompressedStreamTests {
    @Test func bzip2ListsATARPayloadWithModifiedDates() throws {
        let document = try BZip2PreviewAdapter().parse(FileBytes(data: ArchiveTestVectors.bzip2TAR), context: streamContext)
        let object = try listingObject(document)
        #expect(object["archiveFormat"] as? String == "TAR")
        #expect(try listedPaths(document) == samplePaths)
        #expect(try listedEntries(document).allSatisfy { $0["modified"] as? String == ArchiveFixtures.modifiedISO })
    }

    @Test func xzListsATARPayloadWithModifiedDates() throws {
        let document = try XZPreviewAdapter().parse(FileBytes(data: ArchiveTestVectors.xzTAR), context: streamContext)
        #expect(try listedPaths(document) == samplePaths)
        #expect(try listedEntries(document).allSatisfy { $0["modified"] as? String == ArchiveFixtures.modifiedISO })
    }

    @Test func textPayloadsAreReturnedAsTextAndLeftToTheSharedPrivacyFilter() throws {
        let expected = "first line\npassword=synthetic-secret-value\n日本語\n"
        #expect(try BZip2PreviewAdapter().parse(FileBytes(data: ArchiveTestVectors.bzip2Text), context: streamContext).text == expected)
        #expect(try XZPreviewAdapter().parse(FileBytes(data: ArchiveTestVectors.xzText), context: streamContext).text == expected)
        // Plain, non-structured text keeps the shared key/value concealment applicable; the pipeline tests
        // prove the secret never reaches the presentation.
        let document = try BZip2PreviewAdapter().parse(FileBytes(data: ArchiveTestVectors.bzip2Text), context: streamContext)
        #expect(!document.usesStructuredPrivacy)
        #expect(document.syntax == .plain)
    }

    @Test func binaryPayloadsAreReportedWithoutShowingBytes() throws {
        for document in [try BZip2PreviewAdapter().parse(FileBytes(data: ArchiveTestVectors.bzip2Binary), context: streamContext),
                         try XZPreviewAdapter().parse(FileBytes(data: ArchiveTestVectors.xzBinary), context: streamContext)] {
            let object = try listingObject(document)
            #expect(object["payloadKind"] as? String == "binary")
            #expect(object["decodedBytes"] as? Int == 5)
        }
        let bzip2 = try listingObject(BZip2PreviewAdapter().parse(FileBytes(data: ArchiveTestVectors.bzip2Binary), context: streamContext))
        #expect(bzip2["archiveFormat"] as? String == "BZIP2")
        let xz = try listingObject(XZPreviewAdapter().parse(FileBytes(data: ArchiveTestVectors.xzBinary), context: streamContext))
        #expect(xz["archiveFormat"] as? String == "XZ")
    }

    @Test func concatenatedBzip2StreamsDecodeInOrder() throws {
        #expect(try BZip2PreviewAdapter().parse(FileBytes(data: ArchiveTestVectors.bzip2Concatenated), context: streamContext).text == "first\nsecond\n")
    }

    @Test func malformedAndTruncatedStreamsAreRejected() throws {
        let bzip2 = ArchiveTestVectors.bzip2Text
        #expect(throws: PreviewFailure.malformedDocument) { try BZip2PreviewAdapter().parse(FileBytes(data: bzip2.prefix(bzip2.count / 2)), context: streamContext) }
        #expect(throws: PreviewFailure.malformedDocument) { try BZip2PreviewAdapter().parse(FileBytes(data: bzip2.prefix(3)), context: streamContext) }
        #expect(throws: PreviewFailure.malformedDocument) { try BZip2PreviewAdapter().parse(FileBytes(data: Data()), context: streamContext) }
        #expect(throws: PreviewFailure.malformedDocument) { try BZip2PreviewAdapter().parse(FileBytes(data: Data("BZh9not really bzip2 data".utf8)), context: streamContext) }
        var flipped = bzip2
        flipped[flipped.count / 2] ^= 0x10
        #expect(throws: PreviewFailure.malformedDocument) { try BZip2PreviewAdapter().parse(FileBytes(data: flipped), context: streamContext) }
        #expect(throws: PreviewFailure.malformedDocument) { try BZip2PreviewAdapter().parse(FileBytes(data: bzip2 + Data("trailing garbage".utf8)), context: streamContext) }
        let xz = ArchiveTestVectors.xzText
        #expect(throws: PreviewFailure.malformedDocument) { try XZPreviewAdapter().parse(FileBytes(data: xz.prefix(xz.count - 8)), context: streamContext) }
        #expect(throws: PreviewFailure.malformedDocument) { try XZPreviewAdapter().parse(FileBytes(data: Data("not xz".utf8)), context: streamContext) }
    }

    @Test func decompressionBombsStopAtTheDecodedBudget() throws {
        // 8 MiB of one byte compresses to a few hundred bytes; the input budget scales the decoded cap.
        let bomb = ArchiveTestVectors.bzip2Bomb
        #expect(bomb.count < 2_000)
        let budget = PreviewBudget(maxInputBytes: 2_048, maxMilliseconds: 30_000)
        #expect(throws: PreviewFailure.outputTooLarge) { try BZip2PreviewAdapter().parse(FileBytes(data: bomb), context: RequestContext(budget: budget)) }
        let zeros = xzStream(Data(repeating: 0, count: 4 << 20))
        #expect(throws: PreviewFailure.outputTooLarge) { try XZPreviewAdapter().parse(FileBytes(data: zeros), context: RequestContext(budget: PreviewBudget(maxInputBytes: 4_096, maxMilliseconds: 30_000))) }
        #expect(throws: PreviewFailure.inputTooLarge) { try BZip2PreviewAdapter().parse(FileBytes(data: ArchiveTestVectors.bzip2TAR), context: RequestContext(budget: PreviewBudget(maxInputBytes: 64))) }
    }

    private var largeDictionaryStreams: [(String, Data)] {
        [("CRC32", ArchiveTestVectors.xzLargeDictionaryCRC32), ("CRC64", ArchiveTestVectors.xzLargeDictionaryCRC64),
         ("SHA-256", ArchiveTestVectors.xzLargeDictionarySHA256), ("no check", ArchiveTestVectors.xzLargeDictionaryNoCheck),
         ("several blocks", ArchiveTestVectors.xzMultiBlockLargeDictionary)]
    }

    @Test func xzStreamsWithDictionariesAboveEightMiBDecodeThroughTheBoundedPath() throws {
        // Preset 9 records a 64 MiB dictionary; the system decoder is not allowed that, the bounded decoder is.
        let expected = ArchiveTestVectors.xzLargeDictionaryPlain
        for (label, stream) in largeDictionaryStreams {
            let info = try XZPreflight.validate(stream, context: streamContext)
            #expect(info.needsBoundedDecoder, "\(label)")
            let document = try XZPreviewAdapter().parse(FileBytes(data: stream), context: streamContext)
            #expect(Data(document.text.utf8) == expected, "\(label)")
        }
        #expect(try XZPreflight.validate(ArchiveTestVectors.xzMultiBlockLargeDictionary, context: streamContext).blocks.count > 1)
    }

    @Test func xzDictionariesAbove64MiBAreDeclinedBeforeDecoding() {
        #expect(throws: PreviewFailure.inputTooLarge) {
            try XZPreviewAdapter().parse(FileBytes(data: ArchiveTestVectors.xzHugeDictionary), context: streamContext)
        }
    }

    @Test func boundedXZPathChecksTheDeclaredOutputBeforeDecodingAndEveryHeaderAndCheck() throws {
        #expect(throws: PreviewFailure.outputTooLarge) {
            try BoundedDecompression.xz(ArchiveTestVectors.xzLargeDictionaryCRC64, context: streamContext, maximum: 100)
        }
        let expected = ArchiveTestVectors.xzLargeDictionaryPlain
        for (label, stream) in largeDictionaryStreams {
            let bytes = [UInt8](stream)
            for index in bytes.indices {
                var copy = bytes
                copy[index] ^= 0x21
                do {
                    let output = try BoundedDecompression.xz(Data(copy), context: streamContext, maximum: 1 << 20)
                    // A flip may land in an unchecked padding byte; it must never change the decoded data.
                    #expect(output == expected, "\(label) offset \(index) decoded different data")
                } catch let failure as PreviewFailure {
                    #expect([.malformedDocument, .unsupportedFormat, .inputTooLarge, .outputTooLarge, .tooManyNodes].contains(failure), "\(label) offset \(index): \(failure)")
                }
            }
            #expect(throws: PreviewFailure.malformedDocument, "\(label) truncated") {
                try BoundedDecompression.xz(stream.prefix(stream.count - 7), context: streamContext, maximum: 1 << 20)
            }
        }
    }

    @Test func gzipSharesThePayloadRulesWithoutChangingItsOutput() throws {
        let tar = tarArchive([tarEntry(path: "a.txt", mtime: octal(Int(ArchiveFixtures.modified)))])
        let document = try GZIPPreviewAdapter().parse(FileBytes(data: gzip(tar)), context: streamContext)
        #expect(try listedPaths(document) == ["a.txt"])
        #expect(try GZIPPreviewAdapter().parse(FileBytes(data: gzip(Data("plain text\n".utf8))), context: streamContext).text == "plain text\n")
        let binary = try listingObject(GZIPPreviewAdapter().parse(FileBytes(data: gzip(Data([0, 255]))), context: streamContext))
        #expect(binary["archiveFormat"] as? String == "GZIP")
        #expect(binary["payloadKind"] as? String == "binary")
    }

    @Test func tarEntriesCarryTheirModificationTime() throws {
        let stamped = tarEntry(path: "dated.txt", mtime: octal(Int(ArchiveFixtures.modified)))
        let blank = tarEntry(path: "blank.txt", mtime: [UInt8](repeating: 0, count: 12))
        let spaces = tarEntry(path: "spaces.txt", mtime: [UInt8](repeating: 32, count: 12))
        let garbage = tarEntry(path: "garbage.txt", mtime: Array("notoctal999".utf8) + [0])
        let epoch = tarEntry(path: "epoch.txt", mtime: octal(0))
        let data = tarArchive([stamped, blank, spaces, garbage, epoch])
        // Both reading paths share the rule: the incremental random-access reader and the decoded-buffer reader.
        for document in [try TARListingAdapter().parse(DataByteSource(data), context: streamContext),
                         try TARListingAdapter().parse(FileBytes(data: data), context: streamContext)] {
            let entries = try listedEntries(document)
            #expect(entries[0]["modified"] as? String == ArchiveFixtures.modifiedISO)
            #expect(entries[1]["modified"] == nil)
            #expect(entries[2]["modified"] == nil)
            #expect(entries[3]["modified"] == nil)
            #expect(entries[4]["modified"] as? String == "1970-01-01T00:00:00Z")
        }
    }

    @Test func paxModificationTimeOverridesTheHeaderField() throws {
        let record = "22 mtime=1767225600.5\n"
        let paxBody = Array(record.utf8)
        var pax = [UInt8](repeating: 0, count: 512)
        func put(_ bytes: [UInt8], at offset: Int) { for (index, byte) in bytes.enumerated() { pax[offset + index] = byte } }
        put(Array("PaxHeader".utf8), at: 0)
        put(Array("0000644\0".utf8), at: 100)
        put(octal(paxBody.count), at: 124)
        pax[156] = 120
        put(Array("ustar\0".utf8), at: 257)
        for index in 148..<156 { pax[index] = 32 }
        put(Array((String(format: "%06o", pax.reduce(0) { $0 + Int($1) }) + "\0 ").utf8), at: 148)
        let header = Data(pax + paxBody + [UInt8](repeating: 0, count: 512 - paxBody.count))
        let data = tarArchive([header, tarEntry(path: "x.txt", mtime: octal(86_400))])
        let entries = try listedEntries(TARListingAdapter().parse(DataByteSource(data), context: streamContext))
        #expect(entries[0]["modified"] as? String == ArchiveFixtures.modifiedISO)
    }

    @Test func cancellationAndDeadlineAreCheckedBeforeInput() async {
        let task = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try BZip2PreviewAdapter().parse(FileBytes(data: Data()), context: .init(budget: .standard)); return false }
            catch is CancellationError { return true } catch { return false }
        }
        #expect(await task.value)
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try XZPreviewAdapter().parse(FileBytes(data: Data()), context: .init(budget: .init(maxMilliseconds: 0)))
        }
    }
}
