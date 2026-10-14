import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewFormats

/// A pickle fragment and a name for the failure message.
struct PickleCase: Sendable, CustomTestStringConvertible {
    let name: String
    let bytes: [UInt8]
    init(_ name: String, _ bytes: [UInt8]) {
        self.name = name
        self.bytes = bytes
    }
    var testDescription: String { name }
}

@Suite("Pickle opcode walker")
struct PickleWalkerTests {
    private typealias S = PickleStream

    /// Wraps a fragment that leaves one item on the stack so the pickle ends with STOP.
    private static func finished(_ fragment: [UInt8]) -> [UInt8] { fragment + S.stop }

    // MARK: Every opcode, with its argument encoding

    private static let pushing: [PickleCase] = [
        PickleCase("NONE", [0x4E]), PickleCase("INT", S.text("I42\n")), PickleCase("INT bool", S.text("I01\n")),
        PickleCase("LONG", S.text("L123456789012345678901L\n")), PickleCase("FLOAT", S.text("F1.5\n")),
        PickleCase("BININT", [0x4A, 1, 0, 0, 0]), PickleCase("BININT1", [0x4B, 9]), PickleCase("BININT2", [0x4D, 1, 2]),
        PickleCase("BINFLOAT", [0x47, 0x3F, 0xF8, 0, 0, 0, 0, 0, 0]), PickleCase("STRING", S.text("S'abc'\n")),
        PickleCase("BINSTRING", [0x54, 3, 0, 0, 0, 0x61, 0x62, 0x63]), PickleCase("SHORT_BINSTRING", [0x55, 2, 0x61, 0x62]),
        PickleCase("UNICODE", S.text("Vabc\\u00e9\n")), PickleCase("BINUNICODE", S.binUnicode("abc")),
        PickleCase("BINBYTES", [0x42, 2, 0, 0, 0, 1, 2]), PickleCase("SHORT_BINBYTES", [0x43, 2, 1, 2]),
        PickleCase("LONG1", [0x8A, 2, 1, 2]), PickleCase("LONG4", [0x8B, 2, 0, 0, 0, 1, 2]),
        PickleCase("NEWTRUE", [0x88]), PickleCase("NEWFALSE", [0x89]),
        PickleCase("SHORT_BINUNICODE", S.shortUnicode("abc")), PickleCase("BINUNICODE8", [0x8D, 1, 0, 0, 0, 0, 0, 0, 0, 0x61]),
        PickleCase("BINBYTES8", [0x8E, 1, 0, 0, 0, 0, 0, 0, 0, 0x61]), PickleCase("BYTEARRAY8", [0x96, 1, 0, 0, 0, 0, 0, 0, 0, 0x61]),
        PickleCase("EMPTY_TUPLE", [0x29]), PickleCase("EMPTY_LIST", [0x5D]), PickleCase("EMPTY_DICT", [0x7D]),
        PickleCase("EMPTY_SET", [0x8F]), PickleCase("NEXT_BUFFER", [0x97]), PickleCase("PERSID", S.text("Pkey\n")),
        PickleCase("GLOBAL", S.global("collections", "OrderedDict")), PickleCase("EXT1", [0x82, 5]),
        PickleCase("EXT2", [0x83, 5, 0]), PickleCase("EXT4", [0x84, 5, 0, 0, 0])
    ]

    @Test(arguments: pushing)
    func everyValueOpcodeReadsItsArgument(_ fragment: PickleCase) throws {
        let (outcome, _) = try S.walk(Self.finished(fragment.bytes))
        #expect(outcome.ending == .complete, "\(fragment.name)")
        #expect(outcome.endOffset == fragment.bytes.count + 1)
    }

    private static let structural: [PickleCase] = [
        PickleCase("DUP", [0x4E, 0x32]), PickleCase("POP", [0x4E, 0x4E, 0x30]), PickleCase("POP on an empty frame", [0x4E, 0x28, 0x30]),
        PickleCase("POP_MARK", [0x4E, 0x28, 0x4E, 0x4E, 0x31]), PickleCase("PROTO", [0x80, 0x03, 0x4E]),
        PickleCase("FRAME", [0x95, 1, 0, 0, 0, 0, 0, 0, 0, 0x4E]), PickleCase("APPEND", [0x5D, 0x4E, 0x61]),
        PickleCase("APPENDS", [0x5D, 0x28, 0x4E, 0x4E, 0x65]), PickleCase("SETITEM", [0x7D, 0x4E, 0x4E, 0x73]),
        PickleCase("SETITEMS", [0x7D, 0x28, 0x4E, 0x4E, 0x75]), PickleCase("ADDITEMS", [0x8F, 0x28, 0x4E, 0x90]),
        PickleCase("DICT", [0x28, 0x4E, 0x4E, 0x64]), PickleCase("LIST", [0x28, 0x4E, 0x6C]), PickleCase("TUPLE", [0x28, 0x4E, 0x74]),
        PickleCase("TUPLE1", [0x4E, 0x85]), PickleCase("TUPLE2", [0x4E, 0x4E, 0x86]), PickleCase("TUPLE3", [0x4E, 0x4E, 0x4E, 0x87]),
        PickleCase("FROZENSET", [0x28, 0x4E, 0x91]), PickleCase("REDUCE", [0x4E, 0x29, 0x52]), PickleCase("BUILD", [0x4E, 0x4E, 0x62]),
        PickleCase("NEWOBJ", [0x4E, 0x29, 0x81]), PickleCase("NEWOBJ_EX", [0x4E, 0x29, 0x7D, 0x92]),
        PickleCase("OBJ", [0x28, 0x4E, 0x4E, 0x6F]), PickleCase("INST", [0x28, 0x4E] + S.inst("collections", "OrderedDict")),
        PickleCase("BINPERSID", [0x4E, 0x51]), PickleCase("READONLY_BUFFER", [0x4E, 0x98]),
        PickleCase("PUT and GET", [0x4E] + S.text("p0\n") + S.text("g0\n")),
        PickleCase("BINPUT and BINGET", [0x4E, 0x71, 3, 0x68, 3]),
        PickleCase("LONG_BINPUT and LONG_BINGET", [0x4E, 0x72, 9, 0, 0, 0, 0x6A, 9, 0, 0, 0]),
        PickleCase("MEMOIZE", [0x4E, 0x94, 0x68, 0])
    ]

    @Test(arguments: structural)
    func stackOpcodesKeepTheStackConsistent(_ fragment: PickleCase) throws {
        let (outcome, _) = try S.walk(Self.finished(fragment.bytes))
        #expect(outcome.ending == .complete, "\(fragment.name)")
    }

    // MARK: Broken streams

    private static let broken: [PickleCase] = [
        PickleCase("STOP on an empty stack", [0x2E]), PickleCase("no STOP", [0x4E]), PickleCase("empty", []),
        PickleCase("unknown opcode", [0x4E, 0x7F]), PickleCase("unused byte in the documented range", [0x4E, 0x99]),
        PickleCase("APPEND without a list", [0x4E, 0x61, 0x2E]), PickleCase("DUP on an empty stack", [0x32, 0x2E]),
        PickleCase("POP_MARK without a mark", [0x4E, 0x31, 0x2E]), PickleCase("SETITEM with two items", [0x7D, 0x4E, 0x73, 0x2E]),
        PickleCase("APPENDS below the mark", [0x28, 0x4E, 0x65, 0x2E]), PickleCase("OBJ without a class", [0x28, 0x6F, 0x2E]),
        PickleCase("GET of a missing memo entry", [0x68, 0x05, 0x2E]), PickleCase("PROTO 6", [0x80, 0x06, 0x4E, 0x2E]),
        PickleCase("PUT on an empty stack", [0x71, 0x00, 0x2E]), PickleCase("EXT code 0", [0x82, 0x00, 0x2E]),
        PickleCase("negative BINSTRING length", [0x54, 0xFF, 0xFF, 0xFF, 0xFF, 0x2E]),
        PickleCase("unterminated line", S.text("I42")), PickleCase("string longer than the data", [0x58, 100, 0, 0, 0, 0x61, 0x2E]),
        PickleCase("length beyond any file", [0x8E, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x2E]),
        PickleCase("STRING without quotes", S.text("Sabc\n.")), PickleCase("non-digit memo index", S.text("N" + "g1x\n."))
    ]

    @Test(arguments: broken)
    func malformedStreamsAreBrokenAndNeverCrash(_ fragment: PickleCase) throws {
        let (outcome, _) = try S.walk(fragment.bytes)
        #expect(outcome.ending == .broken, "\(fragment.name)")
    }

    @Test func runningOutOfBytesInAWindowIsNotABrokenStream() throws {
        let truncated = Array(S.call("os", "system").dropLast(8))
        #expect(try S.walk(truncated, isWindow: true).outcome.ending == .windowEnd)
        #expect(try S.walk(truncated, isWindow: false).outcome.ending == .broken)
        // An invalid opcode is broken even in a window.
        #expect(try S.walk([0x4E, 0x7F], isWindow: true).outcome.ending == .broken)
    }

    // MARK: Imports

    @Test func protocolZeroTextFormNamesItsImport() throws {
        let (outcome, tally) = try S.walk(S.textCall("os", "system"))
        #expect(outcome.ending == .complete && outcome.protocolVersion == 0 && !outcome.hasProtoHeader)
        #expect(S.kinds(tally) == ["os.system": .code])
        #expect(outcome.imports == 1 && outcome.plausibleImports == 1)
    }

    @Test func installOpcodeTakesItsClassFromTheLines() throws {
        let stream = S.text("(S'x'\n") + S.inst("subprocess", "getoutput") + S.stop
        let (outcome, tally) = try S.walk(stream)
        #expect(outcome.ending == .complete)
        #expect(S.kinds(tally) == ["subprocess.getoutput": .code])
    }

    @Test func stackGlobalResolvesNamesThroughMemoize() throws {
        let stream = S.join(S.proto4, S.shortUnicode("os"), S.memoize, S.shortUnicode("system"), S.memoize, S.stackGlobal,
                            S.memoize, S.shortUnicode("id"), S.tuple1, S.memoize, S.reduce, S.memoize, S.stop)
        let (outcome, tally) = try S.walk(stream)
        #expect(outcome.ending == .complete && outcome.protocolVersion == 4 && outcome.hasProtoHeader)
        #expect(S.kinds(tally) == ["os.system": .code])
    }

    @Test func stackGlobalResolvesNamesThroughPutAndGetInEveryForm() throws {
        let forms: [(String, [UInt8])] = [
            ("BINPUT", S.join(S.shortUnicode("os"), S.binPut(0), S.shortUnicode("system"), S.binPut(1), S.pop, S.pop,
                              S.binGet(0), S.binGet(1), S.stackGlobal, S.stop)),
            ("PUT", S.join(S.text("Vos\n"), S.text("p0\n"), S.text("Vsystem\n"), S.text("p1\n"), S.pop, S.pop,
                           S.text("g0\n"), S.text("g1\n"), S.stackGlobal, S.stop)),
            ("LONG_BINPUT", S.join(S.shortUnicode("os"), [0x72, 7, 0, 0, 0], S.shortUnicode("system"), [0x72, 8, 0, 0, 0], S.pop, S.pop,
                                   [0x6A, 7, 0, 0, 0], [0x6A, 8, 0, 0, 0], S.stackGlobal, S.stop))
        ]
        for (name, stream) in forms {
            let (outcome, tally) = try S.walk(stream)
            #expect(outcome.ending == .complete, "\(name)")
            #expect(S.kinds(tally) == ["os.system": .code], "\(name)")
        }
    }

    @Test func everyStringOpcodeCanSupplyANameForStackGlobal() throws {
        let names: [(String, [UInt8], [UInt8])] = [
            ("STRING with escapes", S.text(#"S'o\x73'"# + "\n"), S.text("S'system'\n")),
            ("SHORT_BINSTRING", [0x55, 2, 0x6F, 0x73], [0x55, 6] + S.text("system")),
            ("BINSTRING", [0x54, 2, 0, 0, 0, 0x6F, 0x73], [0x54, 6, 0, 0, 0] + S.text("system")),
            ("UNICODE with escapes", S.text(#"Vos"# + "\n"), S.text("Vsystem\n")),
            ("BINUNICODE", S.binUnicode("os"), S.binUnicode("system"))
        ]
        for (name, module, attribute) in names {
            let (outcome, tally) = try S.walk(module + attribute + S.stackGlobal + S.stop)
            #expect(outcome.ending == .complete, "\(name)")
            #expect(S.kinds(tally) == ["os.system": .code], "\(name)")
        }
    }

    @Test func aNameTheScanCannotResolveIsRecordedAsSuch() throws {
        let tooLong = S.binUnicode(String(repeating: "a", count: 5_000))
        for stream in [S.join([0x4E, 0x4E], S.stackGlobal, S.stop), S.join(tooLong, S.binUnicode("x"), S.stackGlobal, S.stop)] {
            let (outcome, tally) = try S.walk(stream)
            #expect(outcome.ending == .complete && outcome.imports == 1 && outcome.plausibleImports == 0)
            #expect(S.kinds(tally) == ["unresolved name": .uncommon])
        }
    }

    @Test func extensionCodesAreImportsByNumber() throws {
        let (_, tally) = try S.walk(S.join([0x82, 5], [0x83, 6, 0], [0x84, 7, 0, 0, 0], [0x82, 5], S.stop))
        #expect(S.kinds(tally) == ["extension code 5": .uncommon, "extension code 6": .uncommon, "extension code 7": .uncommon])
        #expect(tally.entries["extension code 5"]?.count == 2)
    }

    @Test func importNamesThatAreNotDottedNamesAreNotPlausible() throws {
        let (outcome, _) = try S.walk(S.text("c a b\nname!\n.") )
        #expect(outcome.imports == 1 && outcome.plausibleImports == 0)
    }

    @Test func theJoblibArrayWrapperIsRemembered() throws {
        let (outcome, _) = try S.walk(S.join(S.global("joblib.numpy_pickle", "NumpyArrayWrapper"), [0x7F]))
        #expect(outcome.ending == .broken && outcome.sawJoblibArray)
    }

    // MARK: The shape torch.save writes

    @Test func anOrdinaryCheckpointImportsOnlyWhatPyTorchExpects() throws {
        let (outcome, tally) = try S.walk(S.torchCheckpoint())
        #expect(outcome.ending == .complete && outcome.protocolVersion == 2 && outcome.hasProtoHeader)
        #expect(outcome.persistentIDs == 1)
        #expect(S.names(tally) == ["collections.OrderedDict", "torch.FloatStorage", "torch._utils._rebuild_tensor_v2"])
        #expect(Set(S.kinds(tally).values) == [.expected])
        #expect(tally.entries["collections.OrderedDict"]?.count == 2)
    }

    @Test func importsBeforeAnInvalidOpcodeAreKeptWhichIsTheShapeOfAnEvasionAttempt() throws {
        let stream = Array(S.call("os", "system").dropLast()) + [0x7F]
        let (outcome, tally) = try S.walk(stream)
        #expect(outcome.ending == .broken && outcome.imports == 1)
        #expect(S.kinds(tally) == ["os.system": .code])
    }

    @Test func persistentIDsAreCounted() throws {
        let (outcome, _) = try S.walk(S.join(S.text("Pone\n"), S.pop, [0x4E, 0x51], S.stop))
        #expect(outcome.persistentIDs == 2)
    }

    // MARK: Caps and cancellation

    @Test func theOpcodeCapEndsTheWalkAndChargesTheSharedBudget() throws {
        let stream = [UInt8](repeating: 0x4E, count: 100) + S.stop
        var budget = 10
        let outcome = try stream.withUnsafeBufferPointer { buffer in
            var walker = PickleWalker(bytes: buffer, start: 0, isWindow: false, tally: PickleImportTally())
            return try walker.run(opcodeBudget: &budget, context: RequestContext(budget: .standard))
        }
        #expect(outcome.ending == .limited && outcome.opcodes == 10 && budget == 0)
    }

    @Test func theStackCapEndsTheWalk() throws {
        #expect(try S.walk([UInt8](repeating: 0x4E, count: PickleWalker.maximumStack + 1)).outcome.ending == .limited)
        #expect(try S.walk([UInt8](repeating: 0x4E, count: PickleWalker.maximumStack) + S.stop).outcome.ending == .complete)
    }

    @Test func theMemoCapEndsTheWalk() throws {
        let step: [UInt8] = [0x4E, 0x94, 0x30]
        let stream = Array((0...PickleWalker.maximumMemo).map { _ in step }.joined())
        #expect(try S.walk(stream).outcome.ending == .limited)
    }

    @Test func theMarkCapEndsTheWalk() throws {
        #expect(try S.walk([UInt8](repeating: 0x28, count: PickleWalker.maximumMarks + 1)).outcome.ending == .limited)
    }

    @Test func retainedStringsAreBoundedInTotal() throws {
        // 1,200 strings of 4 KB would hold 4.8 MB; the walk stays within its cap and still completes.
        let chunk = S.binUnicode(String(repeating: "a", count: 4_000))
        let stream = Array((0..<1_200).map { _ in chunk }.joined()) + [UInt8](repeating: 0x30, count: 1_199) + S.stop
        #expect(try S.walk(stream).outcome.ending == .complete)
    }

    @Test func checkpointsRunEveryFewThousandOpcodes() throws {
        let checkpoints = Mutex(0)
        var context = RequestContext(budget: .standard)
        context.checkpointObserver = { checkpoints.withLock { $0 += 1 } }
        let pair: [UInt8] = [0x4E, 0x30]
        let stream = Array((0..<10_000).map { _ in pair }.joined()) + [0x4E] + S.stop
        _ = try S.walk(stream, context: context)
        #expect(checkpoints.withLock { $0 } >= 5)
    }

    @Test func cancellationStopsTheWalk() async throws {
        let pair: [UInt8] = [0x4E, 0x30]
        let stream = Array((0..<50_000).map { _ in pair }.joined()) + [0x4E] + S.stop
        let observed = Mutex(0)
        let task = Task.detached { () -> Bool in
            var context = RequestContext(budget: .standard)
            context.checkpointObserver = {
                if observed.withLock({ $0 += 1; return $0 }) == 3 { withUnsafeCurrentTask { $0?.cancel() } }
            }
            do { _ = try S.walk(stream, context: context); return false } catch is CancellationError { return true } catch { return false }
        }
        #expect(await task.value)
        #expect(observed.withLock { $0 } == 3)
    }
}
