import AppKit
import Darwin

private struct ContrastCheckFailure: Error, CustomStringConvertible {
    let description: String
}

/// Measures the companion's small-text ink against the fills it is drawn on, in the four appearances a Mac can
/// show: light, dark and the two increased-contrast ones. It resolves the real system colors, so it needs a Mac;
/// it opens no window and changes no setting. Every ratio is printed whether or not it passes, so a Mac session
/// can record them, and every ratio that is too low is reported at the end instead of only the first.
///
/// A dynamic color has a value only while an appearance is current, so a fill and an ink are both turned into
/// sRGB components inside a `performAsCurrentDrawingAppearance` call for the same appearance (`resolved`), and the
/// ink is composited over the fill at its own alpha before the ratio is taken. The ink is also made under every
/// appearance and once under none, then drawn under each: SwiftUI makes it while a view body runs, which is not
/// the appearance it is drawn in, so a color that kept the value it had where it was made would be wrong whenever
/// the two differ. The first Mac run measured 1.18:1 for a hint made under the light appearance and drawn on the
/// dark page.
@main @MainActor
struct CompanionContrastChecks {
    typealias RGBA = (r: Double, g: Double, b: Double, a: Double)
    typealias NamedAppearance = (label: String, appearance: NSAppearance)

    static func main() {
        do { try measure() }
        catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }

    private static func measure() throws {
        try check(abs(contrast((0, 0, 0, 1), (1, 1, 1, 1)) - 21) < 0.000_001,
                  "Fixture: black on white must measure 21:1, or the arithmetic below is wrong")
        let names: [(label: String, name: NSAppearance.Name)] = [
            ("aqua", .aqua),
            ("darkAqua", .darkAqua),
            ("highContrastAqua", .accessibilityHighContrastAqua),
            ("highContrastDarkAqua", .accessibilityHighContrastDarkAqua),
        ]
        var measured = 0
        var failures: [String] = []
        var appearances: [NamedAppearance] = []
        for (label, name) in names {
            // An appearance this Mac cannot make is a failure, reported after every other one has been measured.
            guard let appearance = NSAppearance(named: name) else {
                failures.append("\(label): the appearance is not available on this Mac")
                continue
            }
            appearances.append((label, appearance))
        }
        for (label, appearance) in appearances {
            // The page is what every companion page draws (Color.companionPage); the window color is what the
            // sidebar and the sample's title and status strips draw.
            let page = try resolved(.textBackgroundColor, in: appearance)
            let window = try resolved(.windowBackgroundColor, in: appearance)
            let primary = try resolved(.labelColor, in: appearance)
            // Cards, group headers, the search field and badges are Color.primary at 3 to 8 percent. Here the
            // primary is taken at full strength, a little darker than the label color's own alpha: the harder case.
            let card = over(primary, alpha: 0.04, on: page)
            let header = over(primary, alpha: 0.05, on: card)
            let badge = over(primary, alpha: 0.08, on: card)
            let search = over(primary, alpha: 0.05, on: page)
            let fills: [(fill: String, color: RGBA)] = [
                ("page", page), ("card", card), ("header", header), ("badge", badge), ("search", search),
                ("window", window),
            ]
            let outside = try resolved(CompanionInk.hintColor, in: appearance)
            let chosen = try resolved(CompanionInk.hintInk(for: appearance), in: appearance)
            let link = try resolved(CompanionInk.linkColor, in: appearance)
            let secondary = try resolved(.secondaryLabelColor, in: appearance)
            print("  \(label): page \(describe(page)), window \(describe(window)), label \(describe(primary)), "
                  + "hint \(describe(outside)), chosen \(describe(chosen)), link \(describe(link))")
            var inks: [(origin: String, color: RGBA)] = [("made outside any appearance", outside)]
            for (originLabel, origin) in appearances {
                let made = try resolvedHint(madeUnder: origin, drawnIn: appearance)
                inks.append(("made under \(originLabel)", made))
            }
            inks.append(("chosen for this appearance", chosen))
            // The dynamic hint ink must come out as the ink chosen for the appearance it is drawn in, wherever it
            // was made: that is what tells a color fixed at creation from one resolved at drawing.
            for ink in inks where !same(ink.color, chosen) {
                failures.append("\(label): the hint ink \(ink.origin) resolves to \(describe(ink.color)), "
                                + "not the \(describe(chosen)) chosen for this appearance")
            }
            for (fill, background) in fills {
                let systemRatio = contrast(over(secondary, alpha: secondary.a, on: background), background)
                var firstRatio = 0.0
                for (index, ink) in inks.enumerated() {
                    let ratio = contrast(over(ink.color, alpha: ink.color.a, on: background), background)
                    measured += 1
                    if index == 0 {
                        firstRatio = ratio
                        print("  \(label) on \(fill): hint \(format(ratio)):1 "
                              + "(the system secondary label measures \(format(systemRatio)):1)")
                    } else if abs(ratio - firstRatio) > 0.005 {
                        print("  \(label) on \(fill): hint \(ink.origin) measures \(format(ratio)):1, "
                              + "not \(format(firstRatio)):1")
                    }
                    if ratio < 4.5 {
                        failures.append("\(label): the hint ink \(ink.origin) is \(format(ratio)):1 on the \(fill) fill, "
                                        + "under 4.5:1")
                    }
                }
            }
            let linkRatio = contrast(over(link, alpha: link.a, on: page), page)
            measured += 1
            print("  \(label) on page: link \(format(linkRatio)):1")
            if linkRatio < 4.5 {
                failures.append("\(label): the link ink is \(format(linkRatio)):1 on the page fill, under 4.5:1")
            }
        }
        print("Measured \(measured) companion contrast ratios in \(appearances.count) appearances "
              + "(resolved system colors; no window).")
        guard failures.isEmpty else {
            throw ContrastCheckFailure(description: failures.joined(separator: "\n"))
        }
        print("Passed: every ratio is at least 4.5:1.")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw ContrastCheckFailure(description: message) }
    }

    private static func format(_ value: Double) -> String { String(format: "%.2f", value) }

    /// Whether two colors have the same components, to within what a color space conversion can change.
    private static func same(_ first: RGBA, _ second: RGBA) -> Bool {
        abs(first.r - second.r) < 0.004 && abs(first.g - second.g) < 0.004
            && abs(first.b - second.b) < 0.004 && abs(first.a - second.a) < 0.004
    }

    private static func describe(_ color: RGBA) -> String {
        String(format: "rgba(%.3f, %.3f, %.3f, %.3f)", color.r, color.g, color.b, color.a)
    }

    /// `color` as sRGB components in `appearance`; a dynamic color picks its value for that appearance when it is
    /// converted, so the conversion happens inside the appearance and the components are read afterwards.
    private static func resolved(_ color: NSColor, in appearance: NSAppearance) throws -> RGBA {
        var converted: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            converted = color.usingColorSpace(.sRGB)
        }
        guard let value = converted else {
            throw ContrastCheckFailure(description: "\(color) has no sRGB value under \(appearance.name.rawValue)")
        }
        return (Double(value.redComponent), Double(value.greenComponent),
                Double(value.blueComponent), Double(value.alphaComponent))
    }

    /// The hint ink made while `creation` is the current drawing appearance, then drawn (resolved) under `appearance`.
    private static func resolvedHint(madeUnder creation: NSAppearance, drawnIn appearance: NSAppearance) throws -> RGBA {
        var made: NSColor?
        creation.performAsCurrentDrawingAppearance {
            made = CompanionInk.hintColor
        }
        guard let color = made else {
            throw ContrastCheckFailure(description: "The hint ink could not be made under an appearance")
        }
        return try resolved(color, in: appearance)
    }

    /// `color` drawn at `alpha` over an opaque `background`, per channel in sRGB, as the system composites it.
    private static func over(_ color: RGBA, alpha: Double, on background: RGBA) -> RGBA {
        (color.r * alpha + background.r * (1 - alpha),
         color.g * alpha + background.g * (1 - alpha),
         color.b * alpha + background.b * (1 - alpha),
         1)
    }

    private static func luminance(_ color: RGBA) -> Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }

    /// WCAG 2.x contrast ratio, from 1 to 21.
    private static func contrast(_ first: RGBA, _ second: RGBA) -> Double {
        let one = luminance(first)
        let two = luminance(second)
        return (max(one, two) + 0.05) / (min(one, two) + 0.05)
    }
}
