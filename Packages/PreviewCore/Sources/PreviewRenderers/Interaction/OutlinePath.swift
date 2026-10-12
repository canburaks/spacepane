import Foundation

/// JSONPath-style locations (`$.a.b[2]`) for outline rows, built only from already-concealed node names.
/// Array positions are written `[n]`; keys that are not plain identifiers are bracket-quoted as `['key']`
/// with the RFC 9535 escapes, so the result is one line and unambiguous for any key.
enum OutlinePath {
    /// JSON outlines mark an object parent with this value; an object key spelled like `[0]` is still a key.
    private static let objectMarker = "{…}"

    /// One step from the root down to a row.
    struct Step: Equatable {
        let name: String
        let parentValue: String?
    }

    /// `steps` runs from a top-level row to the row itself. A top-level row named `$` (a JSON document) or
    /// any top-level row when `rootsAreDocuments` is set (one document per row, as in JSON Lines) is the
    /// root and contributes no segment; otherwise the top-level rows are the first keys below `$`.
    static func make(steps: [Step], rootsAreDocuments: Bool = false) -> String {
        guard let first = steps.first else { return "$" }
        let skipsFirst = rootsAreDocuments || first.name == documentRootName
        var path = "$"
        for step in steps.dropFirst(skipsFirst ? 1 : 0) { path += segment(for: step) }
        return path
    }

    /// The name the JSON outline gives its document row.
    private static let documentRootName = "$"

    private static func segment(for step: Step) -> String {
        if step.parentValue != objectMarker, isArrayIndex(step.name) { return step.name }
        if isIdentifier(step.name) { return "." + step.name }
        return "['" + escaped(step.name) + "']"
    }

    private static func isArrayIndex(_ name: String) -> Bool {
        let units = Array(name.utf8)
        guard units.count >= 3, units.first == UInt8(ascii: "["), units.last == UInt8(ascii: "]") else { return false }
        return units[1..<units.count - 1].allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
    }

    /// ASCII identifiers only: anything else is quoted rather than guessing which Unicode a consumer accepts.
    private static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.utf8.first, isIdentifierStart(first) else { return false }
        return name.utf8.dropFirst().allSatisfy { isIdentifierStart($0) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
    }

    private static func isIdentifierStart(_ unit: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(unit) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(unit)
            || unit == UInt8(ascii: "_")
    }

    private static func escaped(_ key: String) -> String {
        var result = ""
        for scalar in key.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "'": result += "\\'"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value)
                    || scalar.value == 0x2028 || scalar.value == 0x2029 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}
