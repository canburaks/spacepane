import Foundation

/// Narrow locale wrapper for the existing MIDI positional formatter. Calendar setters are macOS 10.10 APIs.
enum FactsDurationFormatting {
    static func text(_ seconds: Double, locale: Locale) -> String? {
        guard seconds.isFinite, (0...3600).contains(seconds) else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        var calendar = locale.calendar
        calendar.locale = locale
        formatter.calendar = calendar
        return formatter.string(from: seconds)
    }
}
