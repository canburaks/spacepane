import Foundation
import Testing
@testable import PreviewFormats

@Suite("Pickle import classification")
struct PickleImportClassifierTests {
    private func kind(_ module: String, _ name: String) -> PickleImportKind {
        PickleImportClassifier.classify(module: module, name: name)
    }

    @Test(arguments: [
        ("collections", "OrderedDict"), ("torch._utils", "_rebuild_tensor"), ("torch._utils", "_rebuild_tensor_v2"),
        ("torch._utils", "_rebuild_parameter"), ("torch._utils", "_rebuild_parameter_with_state"),
        ("torch._utils", "_rebuild_qtensor"), ("torch._utils", "_rebuild_sparse_tensor"),
        ("torch._utils", "_rebuild_meta_tensor_no_storage"), ("torch._utils", "_rebuild_wrapper_subclass"),
        ("torch._utils", "_rebuild_device_tensor_from_numpy"), ("torch._utils", "_rebuild_nested_tensor"),
        ("torch._tensor", "_rebuild_from_type_v2"), ("torch", "FloatStorage"), ("torch", "BFloat16Storage"),
        ("torch", "Float8_e4m3fnStorage"), ("torch.storage", "UntypedStorage"), ("torch.storage", "TypedStorage"),
        ("torch", "Size"), ("torch", "device"), ("torch", "float32"), ("torch", "bfloat16"), ("torch", "int64"),
        ("torch", "per_tensor_affine"), ("torch.serialization", "_get_layout"),
        ("numpy.core.multiarray", "_reconstruct"), ("numpy.core.multiarray", "scalar"),
        ("numpy._core.multiarray", "_reconstruct"), ("numpy._core.multiarray", "scalar"),
        ("numpy", "ndarray"), ("numpy", "dtype"), ("_codecs", "encode"),
        ("builtins", "set"), ("builtins", "frozenset"), ("builtins", "slice"), ("builtins", "bytearray"),
        ("builtins", "complex"), ("builtins", "range"), ("__builtin__", "set"), ("__builtin__", "range")
    ])
    func ordinaryCheckpointImportsAreExpected(module: String, name: String) {
        #expect(kind(module, name) == .expected, "\(module).\(name)")
    }

    @Test(arguments: [
        ("os", "system"), ("posix", "system"), ("nt", "system"), ("os", "popen"), ("subprocess", "Popen"),
        ("subprocess", "check_output"), ("pty", "spawn"), ("runpy", "run_path"), ("importlib", "import_module"),
        ("importlib.util", "spec_from_file_location"), ("ctypes", "CDLL"), ("code", "InteractiveInterpreter"),
        ("codeop", "compile_command"), ("commands", "getoutput"), ("popen2", "popen2"),
        ("multiprocessing", "Process"), ("marshal", "loads"), ("types", "FunctionType"), ("types", "CodeType"),
        ("platform", "popen"), ("builtins", "eval"), ("builtins", "exec"), ("__builtin__", "execfile"),
        ("builtins", "compile"), ("builtins", "__import__"), ("builtins", "getattr"), ("builtins", "globals"),
        ("builtins", "locals"), ("builtins", "vars"), ("__builtin__", "apply"), ("builtins", "breakpoint"),
        ("builtins", "input"), ("pickle", "loads"), ("_pickle", "load"), ("cPickle", "loads"),
        ("torch", "load"), ("torch.storage", "_load_from_bytes"), ("torch.utils.collect_env", "run"),
        ("torch.jit", "load"), ("torch.jit._script", "RecursiveScriptModule"),
        ("numpy.testing._private.utils", "runstring"), ("operator", "attrgetter"), ("operator", "methodcaller"),
        ("timeit", "timeit"), ("posixpath", "os.system"), ("builtins", "str.__class__.os.system")
    ])
    func importsThatRunCodeAreCode(module: String, name: String) {
        #expect(kind(module, name) == .code, "\(module).\(name)")
    }

    @Test(arguments: [
        ("socket", "socket"), ("ssl", "SSLContext"), ("urllib.request", "urlopen"), ("urllib2", "urlopen"),
        ("urllib3", "PoolManager"), ("http.client", "HTTPConnection"), ("httplib", "HTTPConnection"),
        ("requests", "get"), ("httpx", "get"), ("aiohttp", "ClientSession"), ("ftplib", "FTP"), ("smtplib", "SMTP"),
        ("telnetlib", "Telnet"), ("webbrowser", "open"), ("shutil", "rmtree"), ("pathlib", "PosixPath"),
        ("tempfile", "mkstemp"), ("glob", "glob"), ("zipfile", "ZipFile"), ("tarfile", "open"),
        ("builtins", "open"), ("__builtin__", "open"), ("io", "open"), ("io", "FileIO"), ("codecs", "open")
    ])
    func importsThatReachTheNetworkOrFilesAreFlaggedAsSuch(module: String, name: String) {
        #expect(kind(module, name) == .networkOrFiles, "\(module).\(name)")
    }

    @Test(arguments: [
        ("sklearn.linear_model._base", "LinearRegression"), ("torch.nn.modules.linear", "Linear"),
        ("torch.nn.parameter", "Parameter"), ("numpy", "array"), ("transformers.models.bert.code", "Thing"),
        ("copyreg", "_reconstructor"), ("builtins", "object"), ("builtins", "str"), ("types", "SimpleNamespace"),
        ("argparse", "Namespace"), ("collections", "defaultdict"), ("io", "BytesIO"), ("platform", "system"),
        ("joblib.numpy_pickle", "NumpyArrayWrapper"), ("pickle", "dumps"), ("torch", "FloatTensor"),
        ("torchvision.models.resnet", "ResNet"), ("torch", "load_state_dict"), ("", "")
    ])
    func everythingElseIsUncommon(module: String, name: String) {
        #expect(kind(module, name) == .uncommon, "\(module).\(name)")
    }

    @Test func aStorageNameMustBeAPlainIdentifier() {
        #expect(kind("torch", "Evil-Storage") == .uncommon)
        #expect(kind("torch", "a.bStorage") == .uncommon)
        #expect(kind("evil", "FloatStorage") == .uncommon)
    }

    @Test func theTallyCountsOccurrencesAndDistinctNamesPerClass() {
        var tally = PickleImportTally()
        tally.record(module: "os", name: "system")
        tally.record(module: "os", name: "system")
        tally.record(module: "posix", name: "system")
        tally.record(module: "socket", name: "socket")
        tally.record(module: "sklearn.tree", name: "DecisionTreeClassifier")
        tally.record(module: "collections", name: "OrderedDict")
        tally.recordExtension(code: 7)
        tally.recordUnresolved()
        #expect(tally.distinctCount(.code) == 2)
        #expect(tally.distinctCount(.networkOrFiles) == 1)
        #expect(tally.distinctCount(.uncommon) == 3)
        #expect(tally.distinctCount(.expected) == 1)
        #expect(tally.count(of: "os.system") == 2)
        #expect(tally.sorted.map(\.name) == ["os.system", "posix.system", "socket.socket", "extension code 7",
                                             "sklearn.tree.DecisionTreeClassifier", "unresolved name", "collections.OrderedDict"])
        #expect(!tally.overflowed)
    }

    @Test func aFloodOfOneClassNeverPushesOutAMoreSeriousOne() {
        var tally = PickleImportTally()
        for index in 0..<10_000 { tally.record(module: "pkg\(index)", name: "Thing") }
        tally.record(module: "os", name: "system")
        #expect(tally.overflowed)
        #expect(tally.distinctCount(.uncommon) == 4_096)
        #expect(tally.distinctCount(.code) == 1)
    }

    @Test func displayedNamesAreClippedAndFreeOfInvisibleCharacters() {
        #expect(PickleImportTally.display("os.system") == "os.system")
        #expect(PickleImportTally.display("evil\u{202E}name\n") == "evil\u{FFFD}name\u{FFFD}")
        #expect(PickleImportTally.display(String(repeating: "a", count: 1_000)).count == PickleImportTally.maximumNameCharacters)
    }

    @Test func aLongNameNeverHidesBehindAHarmlessOneThatSharesItsFirstCharacters() {
        var tally = PickleImportTally()
        let prefix = String(repeating: "x", count: PickleImportTally.maximumNameCharacters)
        tally.record(module: prefix, name: "Harmless")
        tally.record(module: prefix + ".os", name: "system")
        #expect(tally.distinctCount(.uncommon) == 1 && tally.distinctCount(.code) == 1)
        #expect(tally.sorted.first?.entry.kind == .code)
    }
}
