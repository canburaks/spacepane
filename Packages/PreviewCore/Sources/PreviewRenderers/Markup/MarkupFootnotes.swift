import Foundation

/// Footnotes numbered in order of first reference. Markdown references a labelled definition;
/// LaTeX and Org supply the note text at the reference. The numbers are drawn as Unicode
/// superscripts, so they survive copying and need no baseline attributes.
struct MarkupFootnotes {
    /// Footnotes beyond this count are shown as written, which bounds the closing section.
    static let maximumCount = 1_000

    /// Markdown definitions by label, collected before rendering.
    var definitions: [String: String] = [:]
    /// Definition labels in source order, so unreferenced notes can still be shown.
    var definitionOrder: [String] = []
    private(set) var texts: [String] = []
    private var numbers: [String: Int] = [:]

    var isEmpty: Bool { texts.isEmpty }

    /// The number of the footnote labelled `label`, assigning one on first use; nil when undefined or over the bound.
    mutating func reference(label: String) -> Int? {
        if let existing = numbers[label] { return existing }
        guard let text = definitions[label], texts.count < Self.maximumCount else { return nil }
        texts.append(text)
        numbers[label] = texts.count
        return texts.count
    }

    /// Adds an anonymous footnote and returns its number; nil when over the bound.
    mutating func add(text: String) -> Int? {
        guard texts.count < Self.maximumCount else { return nil }
        texts.append(text)
        return texts.count
    }

    /// Appends definitions that no text referenced, in source order.
    mutating func appendUnreferenced() {
        for label in definitionOrder where numbers[label] == nil {
            guard let text = definitions[label], texts.count < Self.maximumCount else { continue }
            texts.append(text)
            numbers[label] = texts.count
        }
    }

    private static let superscriptDigits: [Character] = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]

    static func superscript(_ number: Int) -> String {
        String(String(max(number, 0)).compactMap { $0.wholeNumberValue.map { superscriptDigits[$0] } })
    }
}

extension MarkupBuilder {
    /// Appends the closing "Footnotes" section for block-structured renderers: a localized heading
    /// (collected for Contents) and one line per note, each led by its superscript number. Notes
    /// are plain inline text produced by `render`, so a note never adds structure of its own.
    mutating func appendFootnotes(_ notes: MarkupFootnotes, render: (String) -> MarkupInlineResult) {
        guard !notes.isEmpty else { return }
        ensureBlockSeparation()
        let start = length
        let title = PreviewStrings.text(.markupFootnotes)
        append(title)
        decorate(.heading(2), from: start)
        addHeading(level: 2, title: title, range: NSRange(location: start, length: title.utf16.count))
        for (offset, text) in notes.texts.enumerated() {
            ensureLineStart()
            append(MarkupFootnotes.superscript(offset + 1), style: .footnoteLabel)
            append(" ")
            append(render(text))
        }
    }
}
