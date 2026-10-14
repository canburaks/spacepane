import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewFormats

/// Pickle fixtures are opcode bytes assembled by hand, one opcode at a time (decision 030). Nothing in the
/// tests loads, evaluates or unpickles a stream, and nothing produces one by pickling a live object. Names
/// such as `os.system` appear only as inert bytes.
enum PickleStream {
    static let proto2: [UInt8] = [0x80, 0x02]
    static let proto4: [UInt8] = [0x80, 0x04]
    static let stop: [UInt8] = [0x2E]
    static let mark: [UInt8] = [0x28]
    static let pop: [UInt8] = [0x30]
    static let none: [UInt8] = [0x4E]
    static let emptyTuple: [UInt8] = [0x29]
    static let reduce: [UInt8] = [0x52]
    static let tuple1: [UInt8] = [0x85]
    static let memoize: [UInt8] = [0x94]
    static let stackGlobal: [UInt8] = [0x93]

    static func join(_ parts: [UInt8]...) -> [UInt8] { parts.flatMap { $0 } }
    static func text(_ value: String) -> [UInt8] { Array(value.utf8) }

    static func littleEndian(_ value: Int, width: Int) -> [UInt8] {
        (0..<width).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }

    /// `GLOBAL`: two lines.
    static func global(_ module: String, _ name: String) -> [UInt8] { [0x63] + text(module) + [0x0A] + text(name) + [0x0A] }
    /// `INST`: two lines; the arguments go between a mark and this opcode.
    static func inst(_ module: String, _ name: String) -> [UInt8] { [0x69] + text(module) + [0x0A] + text(name) + [0x0A] }
    /// `BINUNICODE`: a 4-byte length.
    static func binUnicode(_ value: String) -> [UInt8] { [0x58] + littleEndian(value.utf8.count, width: 4) + text(value) }
    /// `SHORT_BINUNICODE`.
    static func shortUnicode(_ value: String) -> [UInt8] { [0x8C, UInt8(value.utf8.count)] + text(value) }
    static func binPut(_ index: UInt8) -> [UInt8] { [0x71, index] }
    static func binGet(_ index: UInt8) -> [UInt8] { [0x68, index] }
    /// A line-form opcode such as `PUT`, `GET` or `INT` followed by its argument.
    static func line(_ opcode: Character, _ argument: String) -> [UInt8] { text(String(opcode) + argument + "\n") }

    /// The shape of the classic exploit, in protocol 0 text form: call `module.name` with one string.
    static func textCall(_ module: String, _ name: String, argument: String = "x") -> [UInt8] {
        text("c\(module)\n\(name)\n(S'\(argument)'\ntR.")
    }

    /// Protocol 2: a global called with one string argument, the way `__reduce__` pickles a call.
    static func call(_ module: String, _ name: String, argument: String = "x") -> [UInt8] {
        join(proto2, global(module, name), binUnicode(argument), tuple1, reduce, stop)
    }

    /// An `OrderedDict` holding one 2 by 2 float tensor, in the shape `torch.save` writes at protocol 2: the
    /// tensor is rebuilt by `torch._utils._rebuild_tensor_v2` from a storage given by a persistent id.
    /// `extraEntry` adds a plain string value under a key before the tensor.
    static func torchCheckpoint(extraEntry: (key: String, value: String)? = nil) -> [UInt8] {
        let dictionary = join(global("collections", "OrderedDict"), binPut(0), emptyTuple, reduce, binPut(1))
        let extra = extraEntry.map { join(binUnicode($0.key), binPut(2), binUnicode($0.value), binPut(3)) } ?? []
        let storage = join(mark, binUnicode("storage"), binPut(4), global("torch", "FloatStorage"), binPut(5),
                           binUnicode("0"), binPut(6), binUnicode("cpu"), binPut(7), [0x4B, 0x04], [0x74], binPut(8), [0x51])
        let rebuild = join(global("torch._utils", "_rebuild_tensor_v2"), binPut(9), mark, storage, [0x4B, 0x00],
                           [0x4B, 0x02, 0x4B, 0x02, 0x86], binPut(10), [0x4B, 0x02, 0x4B, 0x01, 0x86], binPut(11), [0x89],
                           global("collections", "OrderedDict"), binPut(12), emptyTuple, reduce, binPut(13), [0x74],
                           binPut(14), reduce, binPut(15))
        return join(proto2, dictionary, mark, extra, binUnicode("weight"), binPut(16), rebuild, [0x75], stop)
    }

    // MARK: Running the walker

    static func walk(_ bytes: [UInt8], isWindow: Bool = false, opcodeBudget: Int = PickleWalker.maximumOpcodes,
                     context: RequestContext = RequestContext(budget: .standard)) throws -> (outcome: PickleWalkOutcome, tally: PickleImportTally) {
        var remaining = opcodeBudget
        return try bytes.withUnsafeBufferPointer { buffer in
            var walker = PickleWalker(bytes: buffer, start: 0, isWindow: isWindow, tally: PickleImportTally())
            let outcome = try walker.run(opcodeBudget: &remaining, context: context)
            return (outcome, walker.tally)
        }
    }

    /// Import names with their kinds, in the summary's order.
    static func names(_ tally: PickleImportTally) -> [String] { tally.sorted.map(\.name) }
    static func kinds(_ tally: PickleImportTally) -> [String: PickleImportKind] {
        Dictionary(uniqueKeysWithValues: tally.sorted.map { ($0.name, $0.entry.kind) })
    }
}
