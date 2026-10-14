import Foundation
import PreviewContracts

/// How one walk over a pickle stream ended and what it saw.
struct PickleWalkOutcome: Sendable {
    enum Ending: Sendable {
        /// STOP was reached with a consistent stack.
        case complete
        /// An unknown opcode, a stack underflow, a missing memo entry or the end of the data came first.
        case broken
        /// A cap ended the walk. Nothing is known about the rest of the stream.
        case limited
        /// The available bytes are only a leading window of a larger file and ended mid-stream.
        case windowEnd
    }
    var ending: Ending = .broken
    /// The offset after STOP, or the offset where the walk stopped.
    var endOffset = 0
    /// The highest protocol the stream names or needs: its PROTO opcode and the opcodes it uses.
    var protocolVersion = 0
    /// Whether the first opcode was PROTO with a version from 2 to 5.
    var hasProtoHeader = false
    var opcodes = 0
    var persistentIDs = 0
    /// Imports recorded, and how many of them have a name that looks like a Python dotted name.
    var imports = 0
    var plausibleImports = 0
    /// A joblib array wrapper was imported: joblib writes the array's raw bytes between the opcodes, so a walk
    /// that stops after it has reached data and not a broken stream.
    var sawJoblibArray = false
}

/// A bounded, symbolic walk over the opcodes of one pickle (decision 030). It builds no objects, calls
/// nothing and imports nothing. It keeps a stack of "a string, a mark or something else" and a memo, which
/// is enough to resolve the module and the name of `STACK_GLOBAL`, and records every import it meets.
///
/// Caps: 2,000,000 opcodes over all walks of one scan, 100,000 stack items, 100,000 memo entries, 10,000
/// open marks, strings of up to 4 KiB and 4 MiB of retained strings in all.
struct PickleWalker {
    static let maximumOpcodes = 2_000_000
    static let maximumStack = 100_000
    static let maximumMemo = 100_000
    static let maximumMarks = 10_000
    static let maximumRetainedText = 4_194_304
    /// The cancellation and deadline check interval, in opcodes.
    static let checkpointInterval = 4_096

    private enum Symbol {
        case other
        case text(String)
    }

    private var reader: PickleReader
    private let isWindow: Bool
    private var items = ContiguousArray<Symbol>()
    private var marks = ContiguousArray<Int>()
    private var memo: [Int: Symbol] = [:]
    private var retainedText = 0
    private var outcome = PickleWalkOutcome()
    private(set) var tally: PickleImportTally

    /// - Parameters:
    ///   - isWindow: the bytes are the beginning of a larger file, so running out is not a broken stream.
    init(bytes: UnsafeBufferPointer<UInt8>, start: Int, isWindow: Bool, tally: PickleImportTally) {
        reader = PickleReader(bytes: bytes, position: start)
        self.isWindow = isWindow
        self.tally = tally
    }

    /// Walks one pickle. `opcodeBudget` is what is left of the scan's opcode cap and is reduced by what this walk used.
    mutating func run(opcodeBudget: inout Int, context: RequestContext) throws -> PickleWalkOutcome {
        do {
            while true {
                if outcome.opcodes % Self.checkpointInterval == 0 { try context.checkpoint() }
                guard outcome.opcodes < opcodeBudget else { throw PickleBreak.limit }
                let code = try reader.byte()
                outcome.opcodes += 1
                guard let opcode = PickleOpcode(rawValue: code) else { throw PickleBreak.invalid }
                outcome.protocolVersion = max(outcome.protocolVersion, opcode.protocolVersion)
                if try step(opcode) {
                    outcome.ending = .complete
                    break
                }
            }
        } catch PickleBreak.truncated {
            outcome.ending = isWindow ? .windowEnd : .broken
        } catch PickleBreak.invalid {
            outcome.ending = .broken
        } catch PickleBreak.limit {
            outcome.ending = .limited
        }
        opcodeBudget -= outcome.opcodes
        outcome.endOffset = reader.position
        return outcome
    }

    // MARK: Opcodes

    /// Applies one opcode. Returns true at STOP.
    private mutating func step(_ opcode: PickleOpcode) throws -> Bool {
        switch opcode {
        case .stop:
            try require(1)
            return true
        case .mark:
            guard marks.count < Self.maximumMarks else { throw PickleBreak.limit }
            marks.append(items.count)
        case .pop:
            if available > 0 { removeLast(1) } else if !marks.isEmpty { marks.removeLast() } else { throw PickleBreak.invalid }
        case .popMark:
            _ = try popMark()
        case .dup:
            try require(1)
            try push(items[items.count - 1], counted: true)
        case .float, .int, .long:
            _ = try reader.line()
            try push(.other)
        case .binFloat:
            _ = try reader.skip(8)
            try push(.other)
        case .binInt:
            _ = try reader.skip(4)
            try push(.other)
        case .binInt1:
            _ = try reader.skip(1)
            try push(.other)
        case .binInt2:
            _ = try reader.skip(2)
            try push(.other)
        case .noneValue, .newTrue, .newFalse, .emptyTuple, .emptyList, .emptyDict, .emptySet, .nextBuffer:
            try push(.other)
        case .persID:
            _ = try reader.line()
            outcome.persistentIDs += 1
            try push(.other)
        case .binPersID:
            try require(1)
            removeLast(1)
            outcome.persistentIDs += 1
            try push(.other)
        case .reduce, .newObj:
            try require(2)
            removeLast(2)
            try push(.other)
        case .newObjEx:
            try require(3)
            removeLast(3)
            try push(.other)
        case .string:
            let range = try reader.line()
            guard let text = PickleText.quoted(reader.bytes[range]) else { throw PickleBreak.invalid }
            try push(retain(text))
        case .binString:
            let length = try reader.littleEndian(4)
            guard length <= UInt64(Int32.max) else { throw PickleBreak.invalid }
            try pushText(length: length)
        case .shortBinString, .shortBinUnicode:
            try pushText(length: try reader.littleEndian(1))
        case .binUnicode:
            try pushText(length: try reader.littleEndian(4))
        case .binUnicode8:
            try pushText(length: try reader.littleEndian(8))
        case .unicode:
            let range = try reader.line()
            try push(retain(PickleText.rawUnicodeEscape(reader.bytes[range])))
        case .binBytes:
            _ = try reader.skip(try reader.littleEndian(4))
            try push(.other)
        case .shortBinBytes:
            _ = try reader.skip(try reader.littleEndian(1))
            try push(.other)
        case .binBytes8, .byteArray8:
            _ = try reader.skip(try reader.littleEndian(8))
            try push(.other)
        case .long1:
            _ = try reader.skip(try reader.littleEndian(1))
            try push(.other)
        case .long4:
            let length = try reader.littleEndian(4)
            guard length <= UInt64(Int32.max) else { throw PickleBreak.invalid }
            _ = try reader.skip(length)
            try push(.other)
        case .append:
            try require(2)
            removeLast(1)
        case .build:
            try require(2)
            removeLast(1)
        case .setItem:
            try require(3)
            removeLast(2)
        case .appends, .setItems, .addItems:
            _ = try popMark()
            try require(1)
        case .dict, .list, .tuple, .frozenSet:
            _ = try popMark()
            try push(.other)
        case .tuple1:
            try collapse(1)
        case .tuple2:
            try collapse(2)
        case .tuple3:
            try collapse(3)
        case .readonlyBuffer:
            try require(1)
        case .obj:
            guard try popMark() >= 1 else { throw PickleBreak.invalid }
            try push(.other)
        case .global:
            let module = try reader.line()
            let name = try reader.line()
            recordImport(module: reader.text(module), name: reader.text(name))
            try push(.other)
        case .inst:
            let module = try reader.line()
            let name = try reader.line()
            _ = try popMark()
            recordImport(module: reader.text(module), name: reader.text(name))
            try push(.other)
        case .stackGlobal:
            try require(2)
            let name = items[items.count - 1]
            let module = items[items.count - 2]
            removeLast(2)
            if case let .text(moduleText) = module, case let .text(nameText) = name {
                recordImport(module: moduleText, name: nameText)
            } else {
                tally.recordUnresolved()
                outcome.imports += 1
            }
            try push(.other)
        case .ext1, .ext2, .ext4:
            let code = try reader.littleEndian(opcode == .ext1 ? 1 : opcode == .ext2 ? 2 : 4)
            guard code > 0 else { throw PickleBreak.invalid }
            tally.recordExtension(code: code)
            outcome.imports += 1
            try push(.other)
        case .proto:
            let version = try reader.byte()
            guard version <= 5 else { throw PickleBreak.invalid }
            outcome.protocolVersion = max(outcome.protocolVersion, Int(version))
            if outcome.opcodes == 1, version >= 2 { outcome.hasProtoHeader = true }
        case .frame:
            _ = try reader.skip(8)
        case .get:
            try push(try recalled(reader.decimalLine()), counted: true)
        case .binGet:
            try push(try recalled(Int(reader.littleEndian(1))), counted: true)
        case .longBinGet:
            try push(try recalled(Int(reader.littleEndian(4))), counted: true)
        case .put:
            try remember(at: reader.decimalLine())
        case .binPut:
            try remember(at: Int(reader.littleEndian(1)))
        case .longBinPut:
            try remember(at: Int(reader.littleEndian(4)))
        case .memoize:
            try remember(at: memo.count)
        }
        return false
    }

    // MARK: Imports

    private mutating func recordImport(module: String, name: String) {
        tally.record(module: module, name: name)
        outcome.imports += 1
        if Self.isDottedName(module), Self.isDottedName(name) { outcome.plausibleImports += 1 }
        let joined = module + "." + name
        if joined.hasSuffix("numpy_pickle.NumpyArrayWrapper") || joined.hasSuffix("numpy_pickle.NDArrayWrapper") {
            outcome.sawJoblibArray = true
        }
    }

    private static func isDottedName(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy {
            $0 == 0x2E || $0 == 0x5F || (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0)
        }
    }

    // MARK: Stack and memo

    /// Items above the innermost open mark.
    private var available: Int { items.count - (marks.last ?? 0) }

    private func require(_ count: Int) throws {
        guard available >= count else { throw PickleBreak.invalid }
    }

    private mutating func push(_ symbol: Symbol, counted: Bool = false) throws {
        guard items.count < Self.maximumStack else { throw PickleBreak.limit }
        // A duplicated or recalled string is a second holder of the same text.
        if counted, case let .text(text) = symbol {
            if retainedText + text.utf8.count <= Self.maximumRetainedText {
                retainedText += text.utf8.count
                items.append(symbol)
                return
            }
            items.append(.other)
            return
        }
        items.append(symbol)
    }

    private mutating func removeLast(_ count: Int) {
        for _ in 0..<count { release(items.removeLast()) }
    }

    private mutating func release(_ symbol: Symbol) {
        if case let .text(text) = symbol { retainedText -= text.utf8.count }
    }

    /// Removes the items above the innermost mark and the mark; returns how many items that was.
    private mutating func popMark() throws -> Int {
        guard let mark = marks.popLast() else { throw PickleBreak.invalid }
        let count = items.count - mark
        removeLast(count)
        return count
    }

    private mutating func collapse(_ count: Int) throws {
        try require(count)
        removeLast(count)
        try push(.other)
    }

    /// A string kept on the stack, if it is short enough and the retained total allows it.
    private mutating func retain(_ text: String) -> Symbol {
        let size = text.utf8.count
        guard size <= PickleText.maximumBytes, retainedText + size <= Self.maximumRetainedText else { return .other }
        retainedText += size
        return .text(text)
    }

    private mutating func pushText(length: UInt64) throws {
        let range = try reader.skip(length)
        try push(range.count <= PickleText.maximumBytes ? retain(reader.text(range)) : .other)
    }

    private mutating func remember(at index: Int) throws {
        try require(1)
        if let old = memo[index] {
            release(old)
        } else {
            guard memo.count < Self.maximumMemo else { throw PickleBreak.limit }
        }
        var stored = items[items.count - 1]
        if case let .text(text) = stored {
            if retainedText + text.utf8.count <= Self.maximumRetainedText { retainedText += text.utf8.count } else { stored = .other }
        }
        memo[index] = stored
    }

    private func recalled(_ index: Int) throws -> Symbol {
        guard let symbol = memo[index] else { throw PickleBreak.invalid }
        return symbol
    }
}
