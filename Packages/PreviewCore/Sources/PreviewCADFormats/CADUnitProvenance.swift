import Foundation
import PreviewContracts

/// Which unit the displayed CAD extents rest on (decision 027, Q-11). The importer normalizes every model to
/// millimetres, so the numbers are right whatever the file declared; this says whether the file declared a unit,
/// so the presentation can show that unit, and otherwise that millimetres are the importer's normalization.
enum CADUnitProvenance {
    /// A unit the importer reported wins. Without one, an IGES file's own Global section can name it; a STEP file's
    /// unit lives in its data section, which only the importer reads, so STEP stays `.assumedMillimetres` until the
    /// importer reports it.
    static func resolve(reported: GeometryUnitProvenance, kind: CADFileKind,
                        headerFacts: CADHeaderFacts?) -> GeometryUnitProvenance {
        if case .declared = reported { return reported }
        guard kind == .iges, let unit = igesUnit(headerFacts?.sourceUnit) else { return reported }
        return .declared(unit)
    }

    /// The IGES Global-section unit codes (`CADHeaderReader` derives them from the unit flag) that name a
    /// `GeometryLengthUnit`. Miles, kilometres, mils, microinches and unit names a file spells itself are left to the
    /// importer's own conversion to millimetres.
    static func igesUnit(_ code: String?) -> GeometryLengthUnit? {
        guard let code else { return nil }
        switch code {
        case "UM": return .micrometre
        case "MM": return .millimetre
        case "CM": return .centimetre
        case "M": return .metre
        case "IN": return .inch
        case "FT": return .foot
        default: return nil
        }
    }
}
