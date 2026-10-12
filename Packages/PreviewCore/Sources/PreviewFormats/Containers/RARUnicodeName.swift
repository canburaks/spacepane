import Foundation
import PreviewContracts

/// Decodes the compact UTF-16 file-name encoding of RAR 2.x-4.x. The header stores the name in
/// the archiver's byte encoding, a zero byte, then this encoded form. The first byte is a shared
/// high byte; two-bit operations then say how each next unit is produced:
///
/// - `0`: one literal byte is the whole unit (high byte zero)
/// - `1`: one byte is the low byte, the shared high byte is the high byte
/// - `2`: two bytes give the whole unit, low byte first
/// - `3`: a run copies units from the byte-encoded companion name, optionally adding a
///   correction to each byte and using the shared high byte
///
/// An operation byte supplies four operations, most significant pair first.
enum RARUnicodeName {
    /// Longest decoded name in UTF-16 units. A run operation can expand two input bytes into 129
    /// units, so the limit bounds allocation independently of the encoded size.
    static let maximumUnits = 32_768

    static func decode(_ encoded: [UInt8], companion: [UInt8], context: RequestContext) throws -> [UInt16] {
        guard let sharedHigh = encoded.first else { throw PreviewFailure.malformedDocument }
        var position = 1
        var operations: UInt8 = 0
        var remainingOperations = 0
        var units: [UInt16] = []
        func companionByte(_ index: Int) -> UInt16 { index < companion.count ? UInt16(companion[index]) : 0 }
        while position < encoded.count {
            try context.checkpoint()
            guard units.count < maximumUnits else { throw PreviewFailure.malformedDocument }
            if remainingOperations == 0 {
                operations = encoded[position]
                position += 1
                remainingOperations = 4
                continue
            }
            switch operations >> 6 {
            case 0:
                units.append(UInt16(encoded[position]))
                position += 1
            case 1:
                units.append(UInt16(encoded[position]) | UInt16(sharedHigh) << 8)
                position += 1
            case 2:
                guard position + 1 < encoded.count else { throw PreviewFailure.malformedDocument }
                units.append(UInt16(encoded[position]) | UInt16(encoded[position + 1]) << 8)
                position += 2
            default:
                let control = Int(encoded[position])
                position += 1
                if control & 0x80 != 0 {
                    guard position < encoded.count else { throw PreviewFailure.malformedDocument }
                    let correction = UInt16(encoded[position])
                    position += 1
                    for _ in 0..<((control & 0x7F) + 2) {
                        guard units.count < maximumUnits else { throw PreviewFailure.malformedDocument }
                        units.append(((companionByte(units.count) &+ correction) & 0xFF) | UInt16(sharedHigh) << 8)
                    }
                } else {
                    for _ in 0..<(control + 2) {
                        guard units.count < maximumUnits else { throw PreviewFailure.malformedDocument }
                        units.append(companionByte(units.count))
                    }
                }
            }
            operations <<= 2
            remainingOperations -= 1
        }
        return units
    }
}
