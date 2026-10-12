import Foundation
import PreviewRenderers

/// Typographic point values for display. Digits, grouping and the decimal separator follow the display locale
/// and a value keeps at most two fraction digits, so 13 reads "13 pt" and 0.25 reads "0.25 pt". The unit comes
/// from the string catalog, never from this file.
enum TypographyPointFormat {
    /// The number alone, formatted for `locale`.
    static func number(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    /// The value with its unit, for a row, a field or the sample's status line.
    static func text(_ value: Double, locale: Locale = .current, languagePreferences: [String]? = nil) -> String {
        PreviewStrings.format(.typographyPointText, arguments: [number(value, locale: locale)],
                              locale: locale, languagePreferences: languagePreferences)
    }

    /// The value as VoiceOver should read it: "13 points", spelled out for a whole number. A fraction is read
    /// as written, because the plural forms of a fractional count differ by language.
    static func spokenText(_ value: Double, locale: Locale = .current, languagePreferences: [String]? = nil) -> String {
        guard value == value.rounded(), abs(value) < 1_000_000 else {
            return text(value, locale: locale, languagePreferences: languagePreferences)
        }
        return PreviewStrings.count(.typographyPointsSpoken, Int(value), locale: locale,
                                    languagePreferences: languagePreferences)
    }

    /// `value` limited to `range`. A value that is not finite leaves `fallback`, so a pasted "nan" changes nothing.
    static func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
