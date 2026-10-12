import AppKit

/// How strongly an inline code chip is tinted, measured so the code ink stays readable on it (decision 027, Q-72).
///
/// A chip is a little of the foreground laid over the background. Most schemes publish their code color a hair above
/// 4.5:1 on the plain background (decision 023), so a tint toward the text color can push it under. The tint is
/// therefore the strongest rung of a short ladder that keeps the ink at the minimum text contrast on the tinted
/// background, and zero where no rung does: such a span keeps the code face and has no fill. The arithmetic needs no
/// AppKit values (colors are 0xRRGGBB), so tests measure it over every scheme.
enum MarkupSurface {
    /// The fractions of the foreground blended into the background, strongest first.
    static let chipLadder: [Double] = [0.07, 0.05, 0.03]

    /// The strongest rung that keeps `ink` at `NativeSchemePalette.minimumTextContrast` against the tinted
    /// background, or 0 when none does, or when the ink does not reach that contrast on the plain background.
    static func chipTint(background: UInt32, foreground: UInt32, ink: UInt32) -> Double {
        let minimum = NativeSchemePalette.minimumTextContrast
        guard NativeSchemePalette.contrastRatio(ink, background) >= minimum else { return 0 }
        for fraction in chipLadder {
            let tinted = blend(background, foreground, fraction: fraction)
            if NativeSchemePalette.contrastRatio(ink, tinted) >= minimum { return fraction }
        }
        return 0
    }

    /// `foreground` laid over `background` at `fraction` (0 to 1), channel by channel in sRGB, as an opaque fill
    /// composites. A fraction outside 0 to 1 is clamped.
    static func blend(_ background: UInt32, _ foreground: UInt32, fraction: Double) -> UInt32 {
        let amount = min(max(fraction, 0), 1)
        func channel(_ shift: UInt32) -> UInt32 {
            let base = Double((background >> shift) & 0xFF)
            let top = Double((foreground >> shift) & 0xFF)
            return UInt32((base + (top - base) * amount).rounded())
        }
        let red = channel(16), green = channel(8), blue = channel(0)
        return (red << 16) | (green << 8) | blue
    }

    /// A color as 0xRRGGBB in sRGB.
    @MainActor
    static func rgb(of color: NSColor) -> UInt32 {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        func byte(_ component: CGFloat) -> UInt32 { UInt32((min(max(component, 0), 1) * 255).rounded()) }
        let red = byte(srgb.redComponent), green = byte(srgb.greenComponent), blue = byte(srgb.blueComponent)
        return (red << 16) | (green << 8) | blue
    }
}
