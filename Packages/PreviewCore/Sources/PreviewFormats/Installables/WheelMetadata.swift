import Foundation
import PreviewContracts

/// The RFC 822 style headers of a wheel's `METADATA` and `WHEEL` files (decision 030): `Name: value`
/// lines, folded onto following lines that start with a space or tab, ending at the first blank line,
/// where `METADATA` starts its free-text description. Header names compare ignoring ASCII case. Only the
/// names asked for are kept, and each at most `maximumValues` times, so a file of any size costs a
/// bounded amount of memory. Nothing in the text is interpreted or evaluated.
struct WheelHeaders {
    static let maximumValues = 64
    static let maximumValueBytes = 4_096

    private var values: [String: [String]] = [:]

    init(_ data: Data, keeping names: Set<String>, context: RequestContext) throws {
        let bytes = [UInt8](data)
        var current: String?
        var start = 0
        var lineNumber = 0
        while start <= bytes.count {
            if lineNumber.isMultiple(of: 1_024) { try context.checkpoint() }
            lineNumber += 1
            var end = start
            while end < bytes.count, bytes[end] != 0x0A { end += 1 }
            let line = bytes[start..<(end > start && bytes[end - 1] == 0x0D ? end - 1 : end)]
            start = end + 1
            // A blank line ends the headers.
            if line.isEmpty { break }
            if line.first == 0x20 || line.first == 0x09 {
                guard let name = current, var list = values[name], let last = list.last else { continue }
                let folded = Self.text(line)
                guard last.utf8.count + folded.utf8.count < Self.maximumValueBytes else { continue }
                list[list.count - 1] = last.isEmpty ? folded : last + " " + folded
                values[name] = list
                continue
            }
            current = nil
            guard let colon = line.firstIndex(of: 0x3A) else { continue }
            let name = Self.text(line[line.startIndex..<colon]).lowercased()
            guard names.contains(name), (values[name]?.count ?? 0) < Self.maximumValues else { continue }
            current = name
            values[name, default: []].append(PackageSummary.clipped(Self.text(line[line.index(after: colon)...]), limit: Self.maximumValueBytes))
        }
    }

    /// The first value of a header, or `nil` when it is absent or empty.
    func first(_ name: String) -> String? { values[name]?.first(where: { !$0.isEmpty }) }

    func all(_ name: String) -> [String] { (values[name] ?? []).filter { !$0.isEmpty } }

    private static func text(_ bytes: some Collection<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }
}

/// The command names a wheel's `entry_points.txt` installs: the keys of its `[console_scripts]` and
/// `[gui_scripts]` sections. The file is INI-like: `name = module:function`, comments start with `#` or
/// `;`, and an indented line continues the previous value. The targets are never read or imported.
enum WheelEntryPoints {
    static let maximumNames = 256
    private static let sections = ["console_scripts", "gui_scripts"]

    static func commandNames(_ data: Data, context: RequestContext) throws -> [String] {
        var names: [String] = []
        var inScripts = false
        var count = 0
        for line in data.split(whereSeparator: { $0 == 0x0A || $0 == 0x0D }) {
            if count.isMultiple(of: 1_024) { try context.checkpoint() }
            count += 1
            guard let first = line.first, first != 0x20, first != 0x09, first != 0x23, first != 0x3B else { continue }
            let text = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("[") {
                let section = text.dropFirst().prefix { $0 != "]" }.trimmingCharacters(in: .whitespaces)
                inScripts = sections.contains { section.equalsExactly($0) }
                continue
            }
            guard inScripts, names.count < maximumNames, let equals = text.firstIndex(of: "=") else { continue }
            let name = text[..<equals].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !names.contains(where: { $0.equalsExactly(name) }) { names.append(name) }
        }
        return names
    }
}
