import Foundation

/// Tells what a `.pt`, `.pth`, `.ckpt`, `.pickle` or `.joblib` file really is from its first bytes (decision 030).
/// The suffix is never trusted: a file named `.pt` can be a ZIP, a raw pickle, a 7z archive or a model in
/// another format, and a `.pth` can be a Python path file.
enum PickleSniffer {
    /// Bytes read to decide.
    static let headLength = 64

    enum Compression: String, Sendable {
        case zlib, gzip, bzip2, xz
    }

    enum Kind: Equatable, Sendable {
        /// A ZIP archive: the PyTorch 1.6 layout when it holds pickle members.
        case zip
        /// A recognizable file of another kind. The name is the container's technical name.
        case foreign(String)
        /// A joblib file compressed as a whole.
        case compressed(Compression)
        /// Compressed in a way this scan has no decoder for (zstd, lz4, LZMA alone).
        case unsupportedCompression
        /// A raw pickle, or text, or nothing recognizable.
        case other
    }

    static func kind(of head: Data, size: Int64) -> Kind {
        let bytes = [UInt8](head.prefix(headLength))
        func starts(_ prefix: [UInt8]) -> Bool { bytes.starts(with: prefix) }
        if starts([0x50, 0x4B, 0x03, 0x04]) || starts([0x50, 0x4B, 0x05, 0x06]) { return .zip }
        if starts([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return .foreign("7z") }
        if starts(Array("GGUF".utf8)) { return .foreign("GGUF") }
        if starts([0x89, 0x48, 0x44, 0x46, 0x0D, 0x0A, 0x1A, 0x0A]) { return .foreign("HDF5") }
        if starts([0x93] + Array("NUMPY".utf8)) { return .foreign("NumPy") }
        if isSafetensors(bytes, size: size) { return .foreign("safetensors") }
        if starts([0x1F, 0x8B]) { return .compressed(.gzip) }
        if starts([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return .compressed(.xz) }
        if starts(Array("BZh".utf8)), bytes.count > 3, (0x31...0x39).contains(bytes[3]) { return .compressed(.bzip2) }
        // A zlib header with the 32 KiB window zlib writes by default and one of its four compression levels.
        // Only these are taken: a looser test would match the first two bytes of some protocol 0 pickles.
        if bytes.count >= 2, bytes[0] == 0x78, [0x01, 0x5E, 0x9C, 0xDA].contains(bytes[1]) { return .compressed(.zlib) }
        if starts([0x28, 0xB5, 0x2F, 0xFD]) || starts([0x04, 0x22, 0x4D, 0x18]) || starts([0x5D, 0x00, 0x00]) {
            return .unsupportedCompression
        }
        return .other
    }

    /// A safetensors file starts with the 8-byte length of a JSON header, and the header starts with `{`.
    private static func isSafetensors(_ bytes: [UInt8], size: Int64) -> Bool {
        guard bytes.count > 8, bytes[8] == 0x7B else { return false }
        let length = bytes[0..<8].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return length >= 2 && length <= UInt64(max(0, size - 8)) && length <= 104_857_600
    }

    /// The text of data that is valid UTF-8 with no NUL byte, without a byte-order mark; nil otherwise.
    static func utf8Text(_ data: Data) -> String? {
        guard !data.contains(0) else { return nil }
        return String(data: data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data, encoding: .utf8)
    }
}
