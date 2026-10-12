import Foundation

/// The architectures named by an executable's first bytes. Only the thin header or the universal
/// (fat) architecture table is read; load commands, segments and symbols are never parsed.
struct MachOSummary: Equatable {
    enum Layout: String { case thin, universal }
    let layout: Layout
    let architectures: [String]
}

enum MachOHeader {
    /// Enough of the file to hold the thin header or a 16-entry fat table in either width.
    static let prefixLength = 4_096
    static let maximumFatArchitectures = 16

    private static let fatMagic: UInt32 = 0xCAFE_BABE
    private static let fat64Magic: UInt32 = 0xCAFE_BABF
    private static let thinMagics: Set<UInt32> = [0xFEED_FACE, 0xFEED_FACF, 0xCEFA_EDFE, 0xCFFA_EDFE]
    private static let littleEndianMagics: Set<UInt32> = [0xCEFA_EDFE, 0xCFFA_EDFE]

    private static let cpu64Flag: UInt32 = 0x0100_0000
    private static let cpu64With32BitPointers: UInt32 = 0x0200_0000
    private static let cpuTypeX86: UInt32 = 7
    private static let cpuTypeARM: UInt32 = 12
    private static let cpuTypePowerPC: UInt32 = 18
    /// Capability bits occupy the top byte of a CPU subtype; the ARM64E variant is subtype 2 below them.
    private static let subtypeMask: UInt32 = 0x00FF_FFFF
    private static let arm64ESubtype: UInt32 = 2

    static func summary(of header: Data) -> MachOSummary? {
        let bytes = [UInt8](header.prefix(prefixLength))
        guard bytes.count >= 8, let magic = word(bytes, 0, littleEndian: false) else { return nil }
        if magic == fatMagic || magic == fat64Magic {
            let entrySize = magic == fat64Magic ? 32 : 20
            guard let count = word(bytes, 4, littleEndian: false),
                  (1...UInt32(maximumFatArchitectures)).contains(count),
                  8 + Int(count) * entrySize <= bytes.count else { return nil }
            var names: [String] = []
            for index in 0..<Int(count) {
                let offset = 8 + index * entrySize
                guard let type = word(bytes, offset, littleEndian: false),
                      let subtype = word(bytes, offset + 4, littleEndian: false) else { return nil }
                names.append(architecture(type: type, subtype: subtype))
            }
            return MachOSummary(layout: .universal, architectures: names)
        }
        guard thinMagics.contains(magic) else { return nil }
        let little = littleEndianMagics.contains(magic)
        guard bytes.count >= 12, let type = word(bytes, 4, littleEndian: little),
              let subtype = word(bytes, 8, littleEndian: little) else { return nil }
        return MachOSummary(layout: .thin, architectures: [architecture(type: type, subtype: subtype)])
    }

    private static func word(_ bytes: [UInt8], _ offset: Int, littleEndian: Bool) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        let part = bytes[offset..<(offset + 4)]
        let ordered = littleEndian ? Array(part.reversed()) : Array(part)
        return ordered.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    /// Technical architecture names as `lipo` prints them; never localized.
    static func architecture(type: UInt32, subtype: UInt32) -> String {
        let base = type & ~(cpu64Flag | cpu64With32BitPointers)
        let is64 = type & cpu64Flag != 0
        let is64With32 = type & cpu64With32BitPointers != 0
        switch base {
        case cpuTypeX86: return is64 ? "x86_64" : "i386"
        case cpuTypeARM:
            if is64With32 { return "arm64_32" }
            if is64 { return subtype & subtypeMask == arm64ESubtype ? "arm64e" : "arm64" }
            return "arm"
        case cpuTypePowerPC: return is64 ? "ppc64" : "ppc"
        default: return String(format: "cpu 0x%08X", type)
        }
    }
}
