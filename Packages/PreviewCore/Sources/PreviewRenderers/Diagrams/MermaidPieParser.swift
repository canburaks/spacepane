import Foundation

/// A pie chart: optional title and labelled non-negative values.
struct PieDiagramModel: Equatable, Sendable {
    struct Slice: Equatable, Sendable {
        var label: String
        var value: Double
        /// The number as written, shown verbatim beside the label when `showsData` is set.
        var valueText: String
    }

    var title: String?
    var showsData: Bool
    var slices: [Slice]
}

/// Parses `pie [showData] [title …]` followed by `"label" : value` lines.
enum MermaidPieParser {
    /// `remainder` is the text after the `pie` keyword on the header line.
    static func parse(remainder: String, statements: [String]) throws -> PieDiagramModel {
        var title: String?
        var showsData = false
        var rest = remainder.trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("showData") {
            showsData = true
            rest = String(rest.dropFirst("showData".count)).trimmingCharacters(in: .whitespaces)
        }
        if rest.hasPrefix("title") {
            title = DiagramText.singleLine(from: String(rest.dropFirst("title".count)))
        } else if !rest.isEmpty {
            throw DiagramFailure.malformed
        }
        var slices: [PieDiagramModel.Slice] = []
        for raw in statements {
            let statement = raw.trimmingCharacters(in: .whitespaces)
            if statement.isEmpty || MermaidLexing.isComment(statement) { continue }
            let word = MermaidLexing.firstWord(of: statement)
            if word == "title" {
                title = DiagramText.singleLine(from: String(statement.dropFirst("title".count)))
                continue
            }
            if word == "showData" { showsData = true; continue }
            if word == "accTitle" || word == "accDescr" { continue }
            slices.append(try slice(statement))
            guard slices.count <= DiagramLimits.maximumSlices else { throw DiagramFailure.tooLarge }
        }
        guard slices.contains(where: { $0.value > 0 }) else { throw DiagramFailure.malformed }
        return PieDiagramModel(title: title?.isEmpty == true ? nil : title, showsData: showsData, slices: slices)
    }

    /// `"Label" : 42.5`. Only a quoted label and a finite, non-negative number are valid.
    private static func slice(_ statement: String) throws -> PieDiagramModel.Slice {
        guard statement.hasPrefix("\"") else { throw DiagramFailure.malformed }
        let afterQuote = statement.index(after: statement.startIndex)
        guard let close = statement[afterQuote...].firstIndex(of: "\"") else { throw DiagramFailure.malformed }
        let label = DiagramText.singleLine(from: String(statement[afterQuote..<close]))
        var tail = statement[statement.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard tail.hasPrefix(":") else { throw DiagramFailure.malformed }
        tail = String(tail.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard let value = Double(tail), value.isFinite, value >= 0 else { throw DiagramFailure.malformed }
        return .init(label: label, value: value, valueText: tail)
    }
}
