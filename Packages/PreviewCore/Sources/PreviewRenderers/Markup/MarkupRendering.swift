import Foundation
import PreviewContracts

/// Chooses the renderer for a markup-document presentation and derives its models from the
/// already-concealed text. Every renderer produces the same decoration model, and the Rendered,
/// Contents and References views consume it; no view reads source bytes or touches files.
enum MarkupRendering {
    struct Models {
        /// The Rendered text with decorations and headings; nil when a bound was exceeded.
        let document: SafeMarkdownDocument?
        /// The parsed bibliography for the References mode (BibTeX only).
        let references: SafeBibliography?
    }

    /// Formats whose Rendered view is shown first. Markdown joined them with this family so a
    /// previewed document reads as a document, with Source one click away.
    private static let rendersFirst: Set<FormatID> = [.markdown, .latex, .bibtex, .asciidoc, .restructuredText, .org, .fountain]

    static func rendersByDefault(_ formatID: FormatID) -> Bool { rendersFirst.contains(formatID) }

    /// Models for the markup syntaxes handled here. Markdown keeps its own derivation in
    /// `SafePreviewModes`, so this returns nil for it and for every non-markup syntax.
    static func models(for presentation: TextPresentation, locale: Locale) -> Models? {
        let limits = MarkupBuilder.Limits()
        switch presentation.syntax {
        case .bibtex:
            let bibliography = SafeBibliography.parse(presentation.text)
            let document = bibliography.flatMap { BibliographyFormatter.document($0, style: .apa) }
            return Models(document: document, references: document == nil ? nil : bibliography)
        case .latex: return Models(document: LaTeXRenderer.render(presentation.text, limits: limits), references: nil)
        case .asciidoc: return Models(document: AsciiDocRenderer.render(presentation.text, limits: limits), references: nil)
        case .restructuredText: return Models(document: ReStructuredTextRenderer.render(presentation.text, limits: limits), references: nil)
        case .orgMode: return Models(document: OrgRenderer.render(presentation.text, limits: limits), references: nil)
        case .fountain: return Models(document: FountainRenderer.render(presentation.text, limits: limits), references: nil)
        default: return nil
        }
    }

    // MARK: Status notices

    /// Separates the parts of the one-line offline notice.
    private static let noticeSeparator = " · "

    /// The status lines of a rendered document for the mode on screen, in the order they are shown:
    /// - what the renderer left out as a plural-free label-colon line ("Images not loaded: 2 · Linked files not
    ///   loaded: 1"), in Rendered only and only when something was left out, so a document with nothing to load
    ///   carries no resource notice (decision 027, D8 keeps counted text free of plural forms);
    /// - the note that formulas are approximations, in Rendered only;
    /// - the style caveat of a reference list with the note that citation terms stay English, in Rendered and
    ///   References, as one line.
    /// `document` is the model the renderer produced, which carries the counts; nil means none are known.
    static func notices(for presentation: TextPresentation, document: SafeMarkdownDocument?,
                        mode: NativePreviewMode, locale: Locale) -> [String] {
        var lines: [String] = []
        if mode == .rendered, let omitted = document?.omitted, !omitted.isEmpty {
            lines.append(offlineNotice(for: omitted, locale: locale))
        }
        switch presentation.syntax {
        case .bibtex:
            if mode == .rendered || mode == .references {
                lines.append(PreviewStrings.text(.markupReferencesNotice) + " " + PreviewStrings.text(.markupReferencesLanguageNote))
            }
        case .markdown, .latex, .asciidoc, .restructuredText, .orgMode:
            if mode == .rendered, containsMath(presentation.text, syntax: presentation.syntax) {
                lines.append(PreviewStrings.text(.markupMathNotice))
            }
        default: break
        }
        return lines
    }

    /// The notices that need neither a mode nor a model: formulas and the style caveat, as the Rendered view
    /// shows them. It keeps the lines a caller without a mode always had; the preview host calls the overload
    /// that knows the mode and the counts, so Source and Contents carry no document notice.
    static func notices(for presentation: TextPresentation) -> [String] {
        notices(for: presentation, document: nil, mode: .rendered, locale: .current)
    }

    /// "Images not loaded: 2 · Linked files not loaded: 1": one part for each kind that was left out. Counts follow
    /// the presentation locale; the labels are complete translated phrases, so no sentence has to agree with a count.
    private static func offlineNotice(for omitted: OmittedResources, locale: Locale) -> String {
        var parts: [String] = []
        if omitted.images > 0 {
            parts.append(PreviewStrings.format(.documentOmittedImages,
                                               arguments: [omitted.images.formatted(.number.locale(locale))], locale: locale))
        }
        if omitted.linkedFiles > 0 {
            parts.append(PreviewStrings.format(.documentOmittedLinkedFiles,
                                               arguments: [omitted.linkedFiles.formatted(.number.locale(locale))], locale: locale))
        }
        return parts.joined(separator: noticeSeparator)
    }

    private static let inlineDollarMath = try? NSRegularExpression(pattern: #"(?<![\\$])\$(?!\s)[^$\n]+?(?<![\s\\])\$(?!\d)"#)

    /// A cheap, bounded test for the math forms the renderers approximate. It may report a false
    /// positive for text that only resembles a formula; the notice is advisory.
    static func containsMath(_ text: String, syntax: TextSyntax) -> Bool {
        guard text.utf16.count <= MarkupBuilder.Limits().maximumUTF16Units else { return false }
        switch syntax {
        case .latex:
            return text.contains("$") && text.replacingOccurrences(of: "\\$", with: "").contains("$")
                || text.contains("\\(") || text.contains("\\[") || text.contains("\\begin{equation") || text.contains("\\begin{align")
                || text.contains("\\begin{displaymath") || text.contains("\\begin{math")
        case .markdown:
            return text.contains("```math") || text.contains("$$") || hasDollarMath(text)
        case .orgMode:
            return text.contains("\\(") || text.contains("\\[") || text.contains("\\begin{equation") || hasDollarMath(text)
        case .restructuredText:
            return text.contains(":math:") || text.contains(".. math::")
        case .asciidoc:
            return text.contains("latexmath:") || text.contains("stem:[") || text.contains("asciimath:")
                || text.contains("[latexmath]") || text.contains("[stem]")
        default: return false
        }
    }

    private static func hasDollarMath(_ text: String) -> Bool {
        guard text.contains("$"), let inlineDollarMath else { return false }
        return inlineDollarMath.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }
}
