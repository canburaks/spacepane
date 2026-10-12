import Foundation

/// Joins the markup and diagrams families: a Mermaid fence in rendered Markdown (including Markdown
/// produced from ebooks and notebooks) also opens in the Diagram mode. The rendered text keeps the
/// fence as concealed code, so copy, find and selection still see exactly the safe text; the diagram
/// is a separate derived view of that same concealed fence source.
enum MarkdownDiagramFences {
    /// Fences tried per document and the largest fence source parsed; both bound renderer work.
    static let maximumFences = 16
    static let maximumFenceUTF16Units = 65_536

    /// Which fence the Diagram mode draws, out of how many the renderer emitted. A value, not a sentence: the
    /// wording is made from it (`presentationNotice(locale:)`, below) so the limits strip can say what the Diagram
    /// mode left as code.
    struct Receipt: Equatable, Sendable {
        /// The position, counting from one, of the drawn fence among the emitted fences. At most `maximumFences`,
        /// because only that many are tried.
        let selectedIndex: Int
        /// Every diagram fence the renderer emitted, empty, unsupported or beyond the tried prefix included.
        /// Counted from emission, never from the fences that happened to parse.
        let total: Int
    }

    /// The first fence that parses as a supported Mermaid diagram, with the receipt that says which one it was.
    struct Selection: Equatable, Sendable {
        let diagram: SafeDiagram
        let receipt: Receipt
    }

    /// Tries the fences in order, up to `maximumFences`, and reports the first that parses as a supported diagram.
    static func selection(in document: SafeMarkdownDocument, locale: Locale) -> Selection? {
        let text = document.text as NSString
        let ranges = fenceRanges(in: document, text: text)
        for (offset, range) in ranges.prefix(maximumFences).enumerated() {
            guard range.length <= maximumFenceUTF16Units else { continue }
            if let diagram = SafeDiagram.parse(mermaid: text.substring(with: range),
                                               environment: DiagramEnvironment(locale: locale)) {
                return Selection(diagram: diagram, receipt: Receipt(selectedIndex: offset + 1, total: ranges.count))
            }
        }
        return nil
    }

    /// The first fence that parses as a supported Mermaid diagram, or nil.
    static func firstDiagram(in document: SafeMarkdownDocument, locale: Locale) -> SafeDiagram? {
        selection(in: document, locale: locale)?.diagram
    }

    /// The receipt of the fence that `diagram` was parsed from, found without laying anything out again: the fences
    /// of the same bounded prefix are parsed to their models, and the first whose model is the diagram's is the one
    /// drawn. A layout is deterministic for a model and an environment, so a fence whose model equals the drawn one
    /// would have been drawn first. Nil when no tried fence produced `diagram`.
    static func receipt(for diagram: SafeDiagram, in document: SafeMarkdownDocument) -> Receipt? {
        let text = document.text as NSString
        let ranges = fenceRanges(in: document, text: text)
        for (offset, range) in ranges.prefix(maximumFences).enumerated() {
            guard range.length <= maximumFenceUTF16Units,
                  let model = try? MermaidParser.parse(text.substring(with: range)), model == diagram.model else { continue }
            return Receipt(selectedIndex: offset + 1, total: ranges.count)
        }
        return nil
    }

    /// Exact emission boundaries preserve adjacent and empty fences without guessing from styles.
    static func fenceRanges(in document: SafeMarkdownDocument, text: NSString) -> [NSRange] {
        document.diagramFences.map(\.range).filter { range in
            range.location >= 0 && range.length >= 0 && range.location <= text.length
                && range.length <= text.length - range.location
        }
    }
}

extension MarkdownDiagramFences.Receipt {
    /// "Diagram 2 of 3 is drawn". The plural selector is the number of diagrams in the file; both numbers print in
    /// the presentation locale's digits, so no translation carries digits of its own.
    func text(locale: Locale) -> String {
        PreviewStrings.count(.diagramNoticeDrawn, total, additionalArguments: [selectedIndex.formatted(.number.locale(locale))],
                             locale: locale)
    }

    /// The receipt as the preview's typed notice: what stays as code goes to the limits slot at the bottom.
    func presentationNotice(locale: Locale) -> PresentationNotice {
        PresentationNotice(kind: .limit, text: text(locale: locale))
    }
}
