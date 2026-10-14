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

    /// `nil` unless the volume is known and positive, and the unit is declared or assumed to be millimetres. An
    /// undeclared unit leaves the volume's cubic millimetres meaning nothing, so no mass is guessed from it.
    package init?(_ measurements: GeometryMeasurements) {
        guard let volume = measurements.volumeCubicMillimetres, volume > 0,
              measurements.unitProvenance != .undeclared else { return nil }
        massGrams = volume / Self.cubicMillimetresPerCubicCentimetre * Self.plaDensityGramsPerCubicCentimetre
        filamentLengthMetres = volume / Self.filamentCrossSectionSquareMillimetres / Self.millimetresPerMetre
    }
}
