import Foundation
import Testing
import zlib
import PreviewContracts
import PreviewCore
import PreviewFormats

/// Container formats read members and compressed streams under `PreviewBudget.containerScan`, so
/// ordinary archives larger than the 1 MiB text budget list instead of failing as too large.
@Suite("Container scan budget")
struct ContainerBudgetTests {
    @Test func theContainerBudgetIsValidAndOnlyRaisesInputAndTime() {
        let budget = PreviewBudget.containerScan
        #expect(budget.isValid)
        #expect(budget.maxInputBytes == 16_777_216 && budget.maxMilliseconds == 5_000)
        #expect(budget.maxOutputUTF8Bytes == PreviewBudget.standard.maxOutputUTF8Bytes)
        #expect(budget.maxJSONNodes == PreviewBudget.standard.maxJSONNodes)
    }

    @Test func aCompressedTarballLargerThanTheTextBudgetLists() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var generator = SplitMix(seed: 0x5ca1ab1e)
        let payload = Data((0..<1_572_864).map { _ in UInt8(truncatingIfNeeded: generator.next()) })
        let archive = try gzip(tar(name: "payload.bin", contents: payload))
        #expect(archive.count > PreviewBudget.standard.maxInputBytes)
        let url = directory.appendingPathComponent("bundle.tar.gz")
        try archive.write(to: url)
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
        guard case .ready(let presentation) = await pipeline.preview(url: url) else {
            Issue.record("A 1.5 MiB tarball must list under the container budget"); return
        }
        #expect(presentation.text.contains("payload.bin"))
        // An explicit request budget still wins, as thumbnails rely on.
        let small = await pipeline.preview(url: url, budget: PreviewBudget(maxInputBytes: 262_144))
        #expect(small == .unavailable(.inputTooLarge))
        #expect(try Data(contentsOf: url) == archive)
    }

    private func tar(name: String, contents: Data) -> Data {
        var header = [UInt8](repeating: 0, count: 512)
        func put(_ text: String, at offset: Int) { for (index, byte) in text.utf8.enumerated() { header[offset + index] = byte } }
        put(name, at: 0)
        put("0000644", at: 100); put("0000000", at: 108); put("0000000", at: 116)
        put(String(format: "%011o", contents.count), at: 124)
        put("00000000000", at: 136)
        header[156] = UInt8(ascii: "0")
        put("ustar", at: 257); put("00", at: 263)
        for index in 148..<156 { header[index] = 0x20 }
        let checksum = header.reduce(0) { $0 + Int($1) }
        put(String(format: "%06o", checksum), at: 148); header[154] = 0; header[155] = 0x20
        var result = Data(header)
        result.append(contents)
        result.append(Data(count: (512 - contents.count % 512) % 512))
        result.append(Data(count: 1024))
        return result
    }

    private func gzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY,
                            ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw CocoaError(.coderInvalidValue) }
        defer { deflateEnd(&stream) }
        var output = Data(count: Int(deflateBound(&stream, uLong(data.count))))
        let produced = try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) -> Int in
            try output.withUnsafeMutableBytes { (target: UnsafeMutableRawBufferPointer) -> Int in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(data.count)
                stream.next_out = target.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(target.count)
                guard deflate(&stream, Z_FINISH) == Z_STREAM_END else { throw CocoaError(.coderInvalidValue) }
                return target.count - Int(stream.avail_out)
            }
        }
        return output.prefix(produced)
    }
}

/// Deterministic, incompressible test bytes.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
