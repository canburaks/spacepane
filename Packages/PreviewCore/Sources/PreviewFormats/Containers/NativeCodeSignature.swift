import Foundation

/// Recognizes native machine code for `artifact.nativeCode` (decision 030): Mach-O, ELF and Windows PE
/// files by their leading bytes, and native libraries and Node.js add-ons by name. The add-on, package
/// and model adapters share it so they count the same files.
enum NativeCodeSignature {
    /// Leading bytes `isNativeBinary(prefix:)` looks at. A PE header usually starts within the first
    /// few hundred bytes; a header further away is not recognized.
    static let prefixLength = 1_024

    /// Final suffixes of native libraries and add-ons. Versioned shared objects (`libx.so.1.2`) count too.
    static let nativeSuffixes: Set<String> = ["node", "dylib", "so", "dll", "exe", "pyd"]

    static func hasNativeSuffix(_ path: String) -> Bool {
        let name = (path.split(separator: "/").last.map(String.init) ?? path).lowercased()
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return false }
        if nativeSuffixes.contains(String(parts[parts.count - 1])) { return true }
        // `libname.so.1` or `libname.so.1.2.3`: "so" followed only by numeric components.
        guard let so = parts.dropFirst().lastIndex(of: "so"), so < parts.count - 1 else { return false }
        return parts[(so + 1)...].allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
    }

    static func isNativeBinary(prefix data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(prefixLength))
        guard bytes.count >= 4 else { return false }
        func bigEndian32(_ offset: Int) -> UInt32 {
            bytes[offset..<(offset + 4)].reduce(0) { $0 << 8 | UInt32($1) }
        }
        let magic = bigEndian32(0)
        switch magic {
        // Mach-O, 32 and 64 bit, in either byte order.
        case 0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE: return true
        // ELF.
        case 0x7F454C46: return true
        // Universal (fat) Mach-O. Java class files share 0xCAFEBABE, but there the next word is the
        // class-file version (45 or more); a universal binary holds a handful of architectures.
        case 0xCAFEBABE, 0xCAFEBABF:
            return bytes.count >= 8 && (1...30).contains(bigEndian32(4))
        default: break
        }
        // Windows PE: "MZ", then "PE\0\0" at the offset stored at 0x3C.
        guard bytes[0] == 0x4D, bytes[1] == 0x5A, bytes.count >= 0x40 else { return false }
        let offset = bytes[0x3C..<0x40].reversed().reduce(0) { $0 << 8 | Int($1) }
        guard offset >= 0x40, offset + 4 <= bytes.count else { return false }
        return bytes[offset..<(offset + 4)].elementsEqual([0x50, 0x45, 0x00, 0x00])
    }
}
