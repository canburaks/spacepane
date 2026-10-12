import Foundation
import PreviewContracts

/// Temporary font-size zoom for one displayed preview. It is a signed point offset from the saved size, so a
/// later change of the saved size is still honoured, and it is never written anywhere: a new request starts
/// from the saved size again. Every result is clamped into `PreviewTypography.fontSizeRange`.
struct PreviewZoom: Equatable, Sendable {
    /// Proportional steps feel even across the 8–48 pt range; every step still moves by at least one point.
    static let stepRatio = 1.1

    private(set) var offset = 0.0

    var isDefault: Bool { offset == 0 }

    /// The typography to draw with. An invalid base is returned unchanged so renderers keep their own fallback.
    func applying(to base: PreviewTypography) -> PreviewTypography {
        guard !isDefault, base.isValid else { return base }
        var zoomed = base
        zoomed.fontSize = Self.clamp(base.fontSize + offset)
        return zoomed
    }

    /// The zoomed size as a fraction of the saved size (1 at the default). Nil for an invalid base.
    func scale(of base: PreviewTypography) -> Double? {
        guard base.isValid, base.fontSize > 0 else { return nil }
        return applying(to: base).fontSize / base.fontSize
    }

    @discardableResult
    mutating func zoomIn(from base: PreviewTypography) -> Bool {
        let current = applying(to: base).fontSize
        return move(to: max(current + 1, (current * Self.stepRatio).rounded()), from: base)
    }

    @discardableResult
    mutating func zoomOut(from base: PreviewTypography) -> Bool {
        let current = applying(to: base).fontSize
        return move(to: min(current - 1, (current / Self.stepRatio).rounded()), from: base)
    }

    mutating func reset() { offset = 0 }

    /// Returns whether the effective size changed; zooming past either bound is a no-op.
    private mutating func move(to target: Double, from base: PreviewTypography) -> Bool {
        guard base.isValid else { return false }
        let before = applying(to: base).fontSize
        let clamped = Self.clamp(target)
        guard clamped != before else { return false }
        offset = clamped - base.fontSize
        return true
    }

    private static func clamp(_ size: Double) -> Double {
        min(max(size, PreviewTypography.fontSizeRange.lowerBound), PreviewTypography.fontSizeRange.upperBound)
    }
}
