import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// Deterministic fuzzing: seeded mutations of valid streams and of random bytes. A hostile file may fail the
/// preview, but it may never crash, hang or fail with anything other than a `PreviewFailure`.
@Suite("Pickle fuzzing")
struct PickleFuzzTests {
    private typealias S = PickleStream

    /// SplitMix64, so every run sees the same inputs.
    private struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
        mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(max(1, bound))) }
    }

    private func mutated(_ seed: [UInt8], _ random: inout Generator) -> [UInt8] {
        var bytes = seed
        switch random.below(5) {
        case 0: bytes = Array(bytes.prefix(random.below(bytes.count + 1)))
        case 1: for _ in 0..<(1 + random.below(4)) where !bytes.isEmpty { bytes[random.below(bytes.count)] = UInt8(random.below(256)) }
        case 2: if !bytes.isEmpty { bytes.remove(at: random.below(bytes.count)) }
        case 3: bytes.insert(UInt8(random.below(256)), at: random.below(bytes.count + 1))
        default: for _ in 0..<(1 + random.below(3)) where !bytes.isEmpty { bytes[random.below(bytes.count)] ^= UInt8(1 << random.below(8)) }
        }
        return bytes
    }

    @Test func theWalkerEndsCleanlyOnMutatedAndRandomStreams() throws {
        let seeds: [[UInt8]] = [S.torchCheckpoint(), S.call("os", "system"), S.textCall("os", "system"),
                                S.legacyFile(afterPickles: [1, 2, 3, 4]), S.imports([("a", "b"), ("c.d", "e")])]
        var random = Generator(state: 0x5EED)
        for round in 0..<4_000 {
            let stream: [UInt8]
            if round % 4 == 3 {
                // Random bytes, biased towards opcode bytes so the walk gets past its first step.
                let opcodes = Array("(.0123FGIJKLMNPQRSTUVXabcdeghijlopqrstu)]}BC".utf8) + Array(0x80...0x98)
                stream = (0..<random.below(200)).map { _ in random.below(3) == 0 ? UInt8(random.below(256)) : opcodes[random.below(opcodes.count)] }
            } else {
                stream = mutated(seeds[random.below(seeds.count)], &random)
            }
            let (outcome, _) = try S.walk(stream, isWindow: round % 2 == 0)
            #expect(outcome.endOffset <= stream.count && outcome.opcodes <= stream.count + 1, "round \(round)")
        }
    }

    @Test func theAdapterOnlyEverFailsWithAPreviewFailure() {
        let archives = [PyTorchZip.checkpoint(pickle: S.torchCheckpoint()),
                        PyTorchZip.build([.init("archive/data.pkl", S.call("os", "system"), deflated: true)])]
        let others = [PyTorchZip.compress(Data(S.call("os", "system")), windowBits: 15), Data(S.torchCheckpoint()), Data(S.textCall("os", "system"))]
        var random = Generator(state: 0xFEED)
        for round in 0..<3_000 {
            let seed = Array((archives + others)[random.below(archives.count + others.count)])
            let candidate = Data(mutated(seed, &random))
            var context = RequestContext(budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000))
            context.nameHint = PreviewNameHint(filename: round % 2 == 0 ? "a.pt" : "a.pth", suffix: round % 2 == 0 ? "pt" : "pth")
            do { _ = try PickleAdapter().parse(DataByteSource(candidate), context: context) }
            catch is PreviewFailure {}
            catch { Issue.record("round \(round): \(error)") }
        }
    }
}
