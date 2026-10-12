import Foundation

/// Stable persisted identifiers for the archive family added by the competitor-parity program.
/// Each is an independent file-type choice even where adapters share a decompressor or a TAR reader.
public extension FormatID {
    static let rar = FormatID(rawValue: "archive.rar")
    static let sevenZip = FormatID(rawValue: "archive.7z")
    static let bzip2 = FormatID(rawValue: "archive.bzip2")
    static let xz = FormatID(rawValue: "archive.xz")
}
