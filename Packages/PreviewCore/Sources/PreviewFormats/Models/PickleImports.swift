import Foundation

/// What loading a pickle would import, by how much it matters (decision 030). The order is the order the
/// summary lists them in: the entries that matter most come first.
enum PickleImportKind: String, CaseIterable, Sendable {
    /// Can run code: a process, an interpreter, a compiler, a loader.
    case code
    /// Reaches the network or opens and changes files.
    case networkOrFiles
    /// Anything else. Full-model pickles and scikit-learn files land here legitimately.
    case uncommon
    /// What an ordinary PyTorch checkpoint imports: tensor rebuild helpers, storage classes, containers.
    case expected

    var rank: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }
}

/// Classification of `module.name` for the pickle scan. It is a static judgement about the import
/// alone: it cannot tell whether a loaded file would call the import, only that it names it.
///
/// The lists are deliberately conservative. A name is "code" or "network or files" only when it is on
/// a list below; a name that is on no list is "uncommon", which is information and not a verdict.
enum PickleImportClassifier {
    /// Modules whose every attribute can start a process, load or run code, or reach into the interpreter.
    /// `os` is imported as `posix` or `nt` once Python resolves it, so all three are listed.
    private static let codeModules: Set<String> = [
        "os", "posix", "nt", "subprocess", "pty", "runpy", "importlib", "ctypes", "code", "codeop", "commands",
        "popen2", "multiprocessing", "marshal",
        // Well-known gadgets that run a string or a file as code.
        "timeit", "cProfile", "profile", "pdb", "bdb", "pip", "pydoc", "lib2to3"
    ]
    /// The modules a dotted attribute path can reach code through (`posixpath.os.system`). Only these are
    /// judged as the start of a tail, so a package that merely has a submodule called `code` is not.
    private static let tailRoots: Set<String> = ["os", "posix", "nt", "subprocess", "builtins", "__builtin__"]
    private static let builtinModules: Set<String> = ["builtins", "__builtin__"]
    private static let builtinCode: Set<String> = [
        "eval", "exec", "execfile", "compile", "__import__", "getattr", "globals", "locals", "vars", "apply",
        "breakpoint", "input"
    ]
    private static let builtinFiles: Set<String> = ["open", "file"]
    private static let typeCode: Set<String> = ["FunctionType", "CodeType", "LambdaType"]
    /// Modules that load another pickle: loading the file would load that one too.
    private static let loaderModules: Set<String> = ["pickle", "_pickle", "cPickle", "dill", "cloudpickle", "joblib", "numpy", "pandas"]
    private static let loaderNames: Set<String> = ["load", "loads", "read_pickle"]
    private static let codeNames: Set<String> = [
        "platform.popen", "torch.load", "torch.storage._load_from_bytes", "torch.utils.collect_env.run",
        "torch.hub.load", "numpy.testing._private.utils.runstring", "operator.attrgetter", "operator.methodcaller",
        "_operator.attrgetter", "_operator.methodcaller"
    ]
    private static let codePrefixes = ["torch.jit.", "asyncio.subprocess.", "numpy.f2py."]

    private static let networkModules: Set<String> = [
        "socket", "ssl", "urllib", "urllib2", "urllib3", "http", "httplib", "requests", "httpx", "aiohttp", "ftplib",
        "smtplib", "telnetlib", "webbrowser", "shutil", "pathlib", "tempfile", "glob", "zipfile", "tarfile"
    ]
    private static let fileNames: Set<String> = ["io.open", "io.open_code", "io.FileIO", "_io.open", "_io.open_code", "_io.FileIO", "codecs.open"]

    private static let expectedNames: Set<String> = [
        "collections.OrderedDict",
        "torch._utils._rebuild_tensor", "torch._utils._rebuild_tensor_v2", "torch._utils._rebuild_parameter",
        "torch._utils._rebuild_parameter_with_state", "torch._utils._rebuild_qtensor",
        "torch._utils._rebuild_sparse_tensor", "torch._utils._rebuild_meta_tensor_no_storage",
        "torch._utils._rebuild_wrapper_subclass", "torch._utils._rebuild_device_tensor_from_numpy",
        "torch._utils._rebuild_nested_tensor", "torch._tensor._rebuild_from_type_v2",
        "torch.storage.UntypedStorage", "torch.storage.TypedStorage", "torch.Size", "torch.device",
        "torch.serialization._get_layout",
        "numpy.core.multiarray._reconstruct", "numpy.core.multiarray.scalar",
        "numpy._core.multiarray._reconstruct", "numpy._core.multiarray.scalar", "numpy.ndarray", "numpy.dtype",
        "_codecs.encode",
        "builtins.set", "builtins.frozenset", "builtins.slice", "builtins.bytearray", "builtins.complex",
        "builtins.range", "__builtin__.set", "__builtin__.frozenset", "__builtin__.slice", "__builtin__.bytearray",
        "__builtin__.complex", "__builtin__.range"
    ]
    /// Plain attributes of `torch` that a checkpoint stores by name: data types, layouts and quantization schemes.
    private static let torchValues: Set<String> = [
        "float32", "float64", "float16", "bfloat16", "float", "double", "half", "int8", "int16", "int32", "int64",
        "uint8", "uint16", "uint32", "uint64", "bool", "long", "int", "short", "complex32", "complex64", "complex128",
        "cfloat", "cdouble", "qint8", "quint8", "qint32", "quint4x2", "quint2x4", "float8_e4m3fn", "float8_e5m2",
        "float8_e4m3fnuz", "float8_e5m2fnuz", "float8_e8m0fnu",
        "strided", "sparse_coo", "sparse_csr", "sparse_csc", "sparse_bsr", "sparse_bsc",
        "per_tensor_affine", "per_channel_affine", "per_tensor_symmetric", "per_channel_symmetric",
        "per_channel_affine_float_qparams"
    ]

    static func classify(module: String, name: String) -> PickleImportKind {
        let parts = (module + "." + name).split(separator: ".", omittingEmptySubsequences: true).map(String.init)
        guard let root = parts.first else { return .uncommon }
        // A dotted attribute path (protocol 4) can reach a code module through another one, as in
        // `posixpath.os.system`, so a tail that starts at such a module is judged on its own as well.
        if runsCode(parts) { return .code }
        for start in 1..<max(1, parts.count - 1) where tailRoots.contains(parts[start]) && runsCode(Array(parts[start...])) {
            return .code
        }
        if networkModules.contains(root) { return .networkOrFiles }
        if builtinModules.contains(root), parts.count > 1, builtinFiles.contains(parts[1]) { return .networkOrFiles }
        if fileNames.contains(parts.joined(separator: ".")) { return .networkOrFiles }
        if isExpected(module: module, name: name, joined: parts.joined(separator: ".")) { return .expected }
        return .uncommon
    }

    private static func runsCode(_ parts: [String]) -> Bool {
        guard let root = parts.first else { return false }
        let joined = parts.joined(separator: ".")
        if codeModules.contains(root) { return true }
        if builtinModules.contains(root), parts.count > 1 { return builtinCode.contains(parts[1]) }
        if root == "types", parts.count > 1 { return typeCode.contains(parts[1]) }
        if loaderModules.contains(root), let last = parts.last, parts.count > 1, loaderNames.contains(last) { return true }
        return codeNames.contains(joined) || codePrefixes.contains { joined.hasPrefix($0) }
    }

    private static func isIdentifierByte(_ byte: UInt8) -> Bool {
        byte == 0x5F || (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
    }

    private static func isExpected(module: String, name: String, joined: String) -> Bool {
        if expectedNames.contains(joined) { return true }
        guard module == "torch" else { return false }
        if torchValues.contains(name) { return true }
        // Storage classes: `FloatStorage`, `BFloat16Storage`, `Float8_e4m3fnStorage`.
        return name.hasSuffix("Storage") && name.utf8.allSatisfy(isIdentifierByte)
    }
}

/// Distinct imports a scan saw, each with its class and how often it occurred. Bounded: a file that names
/// more distinct imports than a class can keep is flagged as overflowing, and each class keeps its own
/// room so a flood of one class can never push out the entries of a more serious one.
struct PickleImportTally: Sendable {
    struct Entry: Sendable { var count: Int; let kind: PickleImportKind }
    /// A name is shown clipped, so two long names can share a label. The class is part of the key: a name
    /// that runs code must never be counted under a harmless name that shares its first characters.
    private struct Key: Hashable, Sendable {
        let label: String
        let kind: PickleImportKind
    }

    static let maximumNameCharacters = 256
    private static let capacity: [PickleImportKind: Int] = [.code: 1_024, .networkOrFiles: 1_024, .uncommon: 4_096, .expected: 256]
    private static let maximumKnownNames = 8_192

    private var table: [Key: Entry] = [:]
    /// Short qualified names already classified, so a name repeated thousands of times is classified once.
    private var known: [String: PickleImportKind] = [:]
    private var distinct: [PickleImportKind: Int] = [:]
    private(set) var overflowed = false

    var isEmpty: Bool { table.isEmpty }

    /// Distinct names of one class.
    func distinctCount(_ kind: PickleImportKind) -> Int { distinct[kind] ?? 0 }

    /// How many times the shown name occurred, over all classes; nil when it never did.
    func count(of name: String) -> Int? {
        let counts = PickleImportKind.allCases.compactMap { table[Key(label: name, kind: $0)]?.count }
        return counts.isEmpty ? nil : counts.reduce(0, +)
    }

    /// Entries ordered for the summary: by class, then by name.
    var sorted: [(name: String, entry: Entry)] {
        table.map { (name: $0.key.label, entry: $0.value) }.sorted {
            $0.entry.kind.rank != $1.entry.kind.rank ? $0.entry.kind.rank < $1.entry.kind.rank : $0.name < $1.name
        }
    }

    /// Records one import; `module` and `name` are the strings the stream carries, in any encoding.
    mutating func record(module: String, name: String) {
        let qualified = module + "." + name
        let isShort = qualified.utf8.count <= Self.maximumNameCharacters
        let kind: PickleImportKind
        if isShort, let cached = known[qualified] {
            kind = cached
        } else {
            kind = PickleImportClassifier.classify(module: module, name: name)
            if isShort, known.count < Self.maximumKnownNames { known[qualified] = kind }
        }
        add(label: Self.display(qualified), kind: kind)
    }

    /// An import by extension code, which resolves through a registry the loading process fills.
    mutating func recordExtension(code: UInt64) { add(label: "extension code \(code)", kind: .uncommon) }

    /// A name the stream builds while loading, which this scan cannot resolve without running it.
    mutating func recordUnresolved() { add(label: "unresolved name", kind: .uncommon) }

    private mutating func add(label: String, kind: PickleImportKind) {
        let key = Key(label: label, kind: kind)
        if table[key] != nil { table[key]?.count += 1; return }
        guard distinctCount(kind) < Self.capacity[kind, default: 0] else { overflowed = true; return }
        distinct[kind, default: 0] += 1
        table[key] = Entry(count: 1, kind: kind)
    }

    /// The name as the summary shows it: clipped, with controls and invisible format characters replaced,
    /// so a crafted module name cannot reorder or hide the text around it.
    static func display(_ name: String) -> String {
        var result = String.UnicodeScalarView()
        var count = 0
        for scalar in name.unicodeScalars {
            guard count < maximumNameCharacters else { break }
            count += 1
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned, .surrogate:
                result.append("\u{FFFD}")
            default:
                result.append(scalar)
            }
        }
        return String(result)
    }
}
