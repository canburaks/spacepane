import Foundation

/// What printing a measured model as a solid part in PLA would use (Mesh Print Check, decision 029): the mass and the
/// length of filament that fill its volume completely.
///
/// This is an upper bound, not a forecast. A slicer prints most parts with a sparse infill and thin walls, so the
/// real figures are usually well below these, and nothing here knows the printer, the layer settings, the supports or
/// the waste. The volume is the one `GeometryMeasurer` computes for a closed, consistently oriented surface of the
/// displayed tessellation.
package struct GeometryPrintEstimate: Equatable, Sendable {
    /// Density of solid PLA in grams per cubic centimetre, the usual figure for the material (1.24 g/cm³).
    package static let plaDensityGramsPerCubicCentimetre = 1.24
    /// Diameter of the filament most consumer printers take, in millimetres (1.75 mm; the other common size is 2.85 mm).
    package static let filamentDiameterMillimetres = 1.75
    /// Cross-section of that filament in square millimetres: the area of a circle of that diameter.
    package static let filamentCrossSectionSquareMillimetres =
        Double.pi * (filamentDiameterMillimetres / 2) * (filamentDiameterMillimetres / 2)

    private static let cubicMillimetresPerCubicCentimetre = 1_000.0
    private static let millimetresPerMetre = 1_000.0

    /// Mass of a solid PLA part of the measured volume, in grams.
    package let massGrams: Double
    /// Length of filament that makes up that volume, in metres.
    package let filamentLengthMetres: Double

    /// Whether the figures hold only if the model's units are millimetres. True for a model whose unit is undeclared
    /// (every STL, OBJ and PLY file): its cubic millimetres are an assumption, never a statement of the file, so the
    /// estimate is worded as "if the units are millimetres" (decision 027, Q-11). False for a declared unit, and for a
    /// 3MF that omits the attribute, where the specification's default is millimetres.
    package let isConditionalOnMillimetres: Bool

    /// `nil` unless the volume is known and positive, that is, unless the surface is closed and consistently oriented.
    /// The unit decides only how the estimate is worded (`isConditionalOnMillimetres`), not whether there is one.
    package init?(_ measurements: GeometryMeasurements) {
        guard let volume = measurements.volumeCubicMillimetres, volume > 0 else { return nil }
        massGrams = volume / Self.cubicMillimetresPerCubicCentimetre * Self.plaDensityGramsPerCubicCentimetre
        filamentLengthMetres = volume / Self.filamentCrossSectionSquareMillimetres / Self.millimetresPerMetre
        isConditionalOnMillimetres = measurements.unitProvenance == .undeclared
    }
}
