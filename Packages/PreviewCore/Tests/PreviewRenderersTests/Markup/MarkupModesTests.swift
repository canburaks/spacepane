import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private func presentation(_ id: FormatID, _ text: String, syntax: TextSyntax, redactions: Int = 0) -> TextPresentation {
    TextPresentation(formatID: id, text: text, lineCount: text.components(separatedBy: "\n").count,
                     byteCount: text.utf8.count, encoding: .utf8, redactionCount: redactions, syntax: syntax)
}

private let english = Locale(identifier: "en")

@Suite("Markup preview modes")
struct MarkupModesTests {
    @Test func documentsWithTwoOrMoreHeadingsOfferContentsAndOpenRendered() {
        let samples: [(FormatID, TextSyntax, String)] = [
            (.markdown, .markdown, "# One\n\ntext\n\n## Two\n"),
            (.latex, .latex, "\\section{One}\n\\section{Two}"),
            (.asciidoc, .asciidoc, "= One\n\n== Two\n"),
            (.restructuredText, .restructuredText, "One\n===\n\nTwo\n---\n"),
            (.org, .orgMode, "* One\n* Two\n"),
            (.fountain, .fountain, "INT. ONE - DAY\n\nText\n\nEXT. TWO - NIGHT\n\nText")
        ]
        for (id, syntax, text) in samples {
            let modes = SafePreviewModes(presentation(id, text, syntax: syntax), locale: english)
            #expect(modes.available == [.source, .rendered, .contents], "\(id.rawValue)")
            #expect(modes.initialMode(for: id) == .rendered, "\(id.rawValue)")
            #expect(modes.markdown?.headings.count == 2)
            #expect(!modes.hasStructureFallback)
        }
    }

    @Test func oneHeadingOrNoneOffersOnlySourceAndRendered() {
        let single = SafePreviewModes(presentation(.markdown, "# Only\n\ntext", syntax: .markdown), locale: english)
        #expect(single.available == [.source, .rendered])
        let none = SafePreviewModes(presentation(.latex, "plain words", syntax: .latex), locale: english)
        #expect(none.available == [.source, .rendered])
    }

    @Test func bibTeXOffersRenderedAndReferencesAndContentsForItsEntries() {
        let text = "@article{a, author = {X, Y}, title = {T}, year = {2000}}\n@book{b, author = {Z, W}, title = {U}, year = {2001}}"
        let modes = SafePreviewModes(presentation(.bibtex, text, syntax: .bibtex), locale: english)
        #expect(modes.available == [.source, .rendered, .contents, .references])
        #expect(modes.references?.entries.count == 2)
        #expect(modes.initialMode(for: .bibtex) == .rendered)
        #expect(NativePreviewMode.references.title == .markupModeReferences)
        let single = SafePreviewModes(presentation(.bibtex, "@misc{only, title = {T}}", syntax: .bibtex), locale: english)
        #expect(single.available == [.source, .rendered, .references])
    }

    @Test func emptyOrUnparseableBibTeXFallsBackToSource() {
        let modes = SafePreviewModes(presentation(.bibtex, "no entries here", syntax: .bibtex), locale: english)
        #expect(modes.available == [.source])
        #expect(modes.hasStructureFallback)
        #expect(modes.references == nil)
    }

    @Test func documentsBeyondTheRenderBoundFallBackToSource() {
        let huge = String(repeating: "x ", count: 140_000)
        for (id, syntax) in [(FormatID.markdown, TextSyntax.markdown), (.latex, .latex), (.asciidoc, .asciidoc), (.restructuredText, .restructuredText), (.org, .orgMode), (.fountain, .fountain)] {
            let modes = SafePreviewModes(presentation(id, huge, syntax: syntax), locale: english)
            #expect(modes.available == [.source], "\(id.rawValue)")
            #expect(modes.hasStructureFallback)
            #expect(modes.initialMode(for: id) == .source)
        }
    }

    @Test func existingFormatsKeepTheirInitialModes() {
        let json = presentation(.json, "{\"a\": 1}", syntax: .json)
        #expect(SafePreviewModes(json, locale: english).initialMode(for: .json) == .source)
        let plain = presentation(.plainText, "# not a heading", syntax: .plain)
        let modes = SafePreviewModes(plain, locale: english)
        #expect(modes.available == [.source])
        #expect(modes.initialMode(for: .plainText) == .source)
        #expect(!MarkupRendering.rendersByDefault(.plainText))
    }

    @Test func notebookRenderedDocumentsGainContentsWithoutChangingTheirInitialMode() {
        let notebook = ###"{"nbformat":4,"cells":[{"cell_type":"markdown","metadata":{},"source":["# A\n","text\n","## B"]}]}"###
        let modes = SafePreviewModes(presentation(.jupyterNotebook, notebook, syntax: .json), locale: english)
        #expect(modes.markdown?.headings.map(\.title) == ["A", "B"])
        #expect(modes.available.contains(.contents))
        #expect(modes.initialMode(for: .jupyterNotebook) == .rendered)
    }

    @Test func derivedModelsComeOnlyFromConcealedText() {
        let text = "# Title\n\npassword: ••••\n\n## Next\n"
        let modes = SafePreviewModes(presentation(.markdown, text, syntax: .markdown, redactions: 1), locale: english)
        #expect(modes.markdown?.text.contains("password: ••••") == true)
        #expect(modes.markdown?.headings.map(\.title) == ["Title", "Next"])
    }

    @Test func mathNoticeAppearsOnlyWhenFormulasAreApproximated() {
        // The Rendered view's lines; `theMathNoticeShowsOnlyInRendered` covers the other modes.
        let math = presentation(.latex, "$x^2$ and more", syntax: .latex)
        #expect(notices(math, mode: .rendered).contains(PreviewStrings.text(.markupMathNotice)))
        let cost = presentation(.markdown, "It costs $5 and $6", syntax: .markdown)
        #expect(notices(cost, mode: .rendered).isEmpty)
        let markdownMath = presentation(.markdown, "Euler: $e^{i\\pi}$", syntax: .markdown)
        #expect(notices(markdownMath, mode: .rendered) == [PreviewStrings.text(.markupMathNotice)])
        let fence = presentation(.markdown, "```math\nx\n```", syntax: .markdown)
        #expect(notices(fence, mode: .rendered) == [PreviewStrings.text(.markupMathNotice)])
        let rst = presentation(.restructuredText, "Text :math:`x`", syntax: .restructuredText)
        #expect(notices(rst, mode: .rendered) == [PreviewStrings.text(.markupMathNotice)])
        let none = presentation(.restructuredText, "No formulas", syntax: .restructuredText)
        #expect(notices(none, mode: .rendered).isEmpty)
        let escaped = presentation(.latex, "price \\$5", syntax: .latex)
        #expect(notices(escaped, mode: .rendered).isEmpty)
    }

    @Test func everyNewStringIsTranslatedForEveryNonEnglishLanguage() {
        let translated: [PreviewStrings.Key] = [
            .markupAlertNote, .markupAlertTip, .markupAlertImportant, .markupAlertWarning, .markupAlertCaution,
            .markupFootnotes, .markupMathNotice, .markupModeReferences, .markupContentsItem, .markupContentsHelp,
            .markupReferencesStyleLabel, .markupReferencesAccessibility, .markupReferencesNotice, .markupStyleChicago
        ]
        let languages = ["tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        for key in translated {
            let english = PreviewStrings.text(key, languagePreferences: ["en"])
            for language in languages {
                // "Important" is the same word in French.
                if key == .markupAlertImportant, language == "fr" { continue }
                #expect(PreviewStrings.text(key, languagePreferences: [language]) != english, "\(key.rawValue) \(language)")
            }
        }
        // Technical style names are the same everywhere by design.
        for key in [PreviewStrings.Key.markupStyleAPA, .markupStyleMLA, .markupStyleIEEE] {
            for language in languages { #expect(PreviewStrings.text(key, languagePreferences: [language]) == PreviewStrings.text(key, languagePreferences: ["en"])) }
        }
        #expect(PreviewStrings.text(.markupAlertNote, languagePreferences: ["de"]) == "Hinweis")
    }

    @Test func formattedStringsKeepTheirPositionalPlaceholdersInEveryLanguage() {
        for language in ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"] {
            let item = String(format: PreviewStrings.text(.markupContentsItem, languagePreferences: [language]), locale: Locale(identifier: language), 3 as Int64, "Heading" as NSString)
            #expect(item.contains("3") || item.contains("३") || item.contains("৩"), "\(language): \(item)")
            #expect(item.contains("Heading"), "\(language)")
            let references = String(format: PreviewStrings.text(.markupReferencesAccessibility, languagePreferences: [language]), locale: Locale(identifier: language), 12 as Int64)
            #expect(!references.contains("%"), "\(language)")
        }
    }

    @Test func bibTeXShowsTheStyleCaveatWithTheNoteThatCitationTermsStayEnglish() {
        let bib = presentation(.bibtex, "@misc{a, title = {T}}", syntax: .bibtex)
        // One status line: the caveat, then the recorded exception for the style guides' English terms (decision 015).
        let line = PreviewStrings.text(.markupReferencesNotice) + " " + PreviewStrings.text(.markupReferencesLanguageNote)
        #expect(notices(bib, mode: .rendered) == [line])
        #expect(notices(bib, mode: .references) == [line])
    }

    @Test func spaceholderRenderingsAreNotProducedForOtherSyntaxes() {
        for syntax in [TextSyntax.plain, .json, .yaml, .sourceCode, .commaSeparated, .xml] {
            let value = presentation(.plainText, "text", syntax: syntax)
            #expect(MarkupRendering.models(for: value, locale: english) == nil)
            #expect(MarkupRendering.notices(for: value).isEmpty)
        }
    }

    // MARK: Notices that know the mode and what was left out (decision 027, Q-14; review DM-06 and DM-16)

    private func notices(_ value: TextPresentation, mode: NativePreviewMode, locale: Locale = english) -> [String] {
        let modes = SafePreviewModes(value, locale: locale)
        return MarkupRendering.notices(for: value, document: modes.markdown, mode: mode, locale: locale)
    }

    private func imagesLine(_ count: String) -> String {
        PreviewStrings.format(.documentOmittedImages, arguments: [count], locale: english)
    }

    private func filesLine(_ count: String) -> String {
        PreviewStrings.format(.documentOmittedLinkedFiles, arguments: [count], locale: english)
    }

    @Test func aDocumentWithNothingToLoadCarriesNoResourceNotice() {
        let samples: [(FormatID, TextSyntax, String)] = [
            (.markdown, .markdown, "# One\n\n[a link](https://example.invalid) and `![code](a.png)`"),
            (.latex, .latex, "\\section{One}\nText with \\href{https://example.invalid}{a link}."),
            (.asciidoc, .asciidoc, "= One\n\nSee https://example.invalid[a link]."),
            (.restructuredText, .restructuredText, "One\n===\n\nSee `a link <https://example.invalid>`_."),
            (.org, .orgMode, "* One\nSee [[https://example.invalid][a link]]."),
            (.fountain, .fountain, "INT. ONE - DAY\n\nText")
        ]
        for (id, syntax, text) in samples {
            let value = presentation(id, text, syntax: syntax)
            #expect(SafePreviewModes(value, locale: english).markdown?.omitted.isEmpty == true, "\(id.rawValue)")
            #expect(notices(value, mode: .rendered).isEmpty, "\(id.rawValue)")
        }
    }

    @Test func whatEachDialectLeavesOutIsCountedAndNamedInOneLabelColonLine() {
        let samples: [(id: FormatID, syntax: TextSyntax, text: String, expected: OmittedResources, line: String)] = [
            (.markdown, .markdown, "![a](https://x.invalid/a.png) and ![b](b.png) and ![c](data:image/png;base64,AA==)",
             OmittedResources(remoteImages: 1, localImages: 1), imagesLine("2")),
            (.asciidoc, .asciidoc, "image::a.png[Alt]\n\nSee image:https://x.invalid/b.png[B] now.\n\ninclude::part.adoc[]",
             OmittedResources(remoteImages: 1, localImages: 1, linkedFiles: 1), imagesLine("2") + " · " + filesLine("1")),
            (.restructuredText, .restructuredText, ".. image:: a.png\n\n.. figure:: https://x.invalid/b.png\n\n   Caption text\n\n.. include:: part.rst",
             OmittedResources(remoteImages: 1, localImages: 1, linkedFiles: 1), imagesLine("2") + " · " + filesLine("1")),
            (.latex, .latex, "\\begin{document}\n\\includegraphics[width=3cm]{figure.png}\n\\input{chapter-two}\n\\include{appendix}\n\\end{document}",
             OmittedResources(localImages: 1, linkedFiles: 2), imagesLine("1") + " · " + filesLine("2")),
            (.org, .orgMode, "#+INCLUDE: \"other.org\"\n\n[[./pic.png]] and [[https://x.invalid/b.jpg]] and [[./notes.org][Notes]] done",
             OmittedResources(remoteImages: 1, localImages: 1, linkedFiles: 1), imagesLine("2") + " · " + filesLine("1"))
        ]
        for sample in samples {
            let value = presentation(sample.id, sample.text, syntax: sample.syntax)
            #expect(SafePreviewModes(value, locale: english).markdown?.omitted == sample.expected, "\(sample.id.rawValue)")
            #expect(notices(value, mode: .rendered) == [sample.line], "\(sample.id.rawValue)")
            // Source shows the text as written and Contents lists headings: neither says anything was left out.
            #expect(notices(value, mode: .source).isEmpty, "\(sample.id.rawValue)")
            #expect(notices(value, mode: .contents).isEmpty, "\(sample.id.rawValue)")
        }
    }

    @Test func aNotebookCountsTheImagesOfItsMarkdownCells() {
        let notebook = ###"{"nbformat":4,"cells":[{"cell_type":"markdown","metadata":{},"source":["![fig](https://example.invalid/i.png)"]}]}"###
        let value = presentation(.jupyterNotebook, notebook, syntax: .json)
        #expect(SafePreviewModes(value, locale: english).markdown?.omitted == OmittedResources(remoteImages: 1))
        #expect(notices(value, mode: .rendered) == [imagesLine("1")])
        #expect(notices(value, mode: .source).isEmpty)
    }

    @Test func countsFollowThePresentationLocaleAndNeverTheInterfaceLanguageOfTheFile() {
        let document = SafeMarkdownDocument(text: "", decorations: [], omitted: OmittedResources(localImages: 1_234))
        let value = presentation(.markdown, "", syntax: .markdown)
        let american = MarkupRendering.notices(for: value, document: document, mode: .rendered, locale: Locale(identifier: "en_US"))
        let german = MarkupRendering.notices(for: value, document: document, mode: .rendered, locale: Locale(identifier: "de_DE"))
        #expect(american.count == 1 && american[0].contains("1,234"))
        #expect(german.count == 1 && german[0].contains("1.234"))
    }

    @Test func theMathNoticeShowsOnlyInRendered() {
        let math = presentation(.latex, "$x^2$ and more", syntax: .latex)
        #expect(notices(math, mode: .rendered) == [PreviewStrings.text(.markupMathNotice)])
        #expect(notices(math, mode: .source).isEmpty)
        #expect(notices(math, mode: .contents).isEmpty)
        let markdown = presentation(.markdown, "Euler: $e^{i\\pi}$", syntax: .markdown)
        #expect(notices(markdown, mode: .rendered) == [PreviewStrings.text(.markupMathNotice)])
        #expect(notices(markdown, mode: .source).isEmpty)
    }

    @Test func theCitationCaveatShowsOnceInRenderedAndReferencesAndNeverInSourceOrContents() {
        let bib = presentation(.bibtex, "@misc{a, title = {T}}", syntax: .bibtex)
        let caveat = PreviewStrings.text(.markupReferencesNotice)
        let note = PreviewStrings.text(.markupReferencesLanguageNote)
        for mode in [NativePreviewMode.rendered, .references] {
            let lines = notices(bib, mode: mode)
            #expect(lines.count == 1, "\(mode)")
            #expect(lines.first?.hasPrefix(caveat) == true && lines.first?.hasSuffix(note) == true, "\(mode)")
        }
        #expect(notices(bib, mode: .source).isEmpty)
        #expect(notices(bib, mode: .contents).isEmpty)
    }

    @Test func theModelessEntryPointKeepsTheLinesItsCallersAlwaysHad() {
        let math = presentation(.latex, "$x^2$", syntax: .latex)
        #expect(MarkupRendering.notices(for: math) == [PreviewStrings.text(.markupMathNotice)])
        let bib = presentation(.bibtex, "@misc{a, title = {T}}", syntax: .bibtex)
        #expect(MarkupRendering.notices(for: bib) == notices(bib, mode: .rendered))
        // No model means no counts, so it never claims anything was left out.
        #expect(MarkupRendering.notices(for: presentation(.markdown, "![a](b.png)", syntax: .markdown)).isEmpty)
    }

    @Test func theBuilderAddsUpWhatItWasToldAndWhatInlineRunsCarry() {
        var builder = MarkupBuilder()
        builder.noteOmitted(.linkedFile)
        builder.append(MarkupInlineResult(text: "x", decorations: [], omitted: OmittedResources(remoteImages: 2)))
        builder.noteOmitted(.localImage)
        let document = builder.finish()
        #expect(document?.omitted == OmittedResources(remoteImages: 2, localImages: 1, linkedFiles: 1))
        #expect(document?.omitted.images == 3)
        #expect(OmittedResources().isEmpty)
        #expect(MarkupBuilder().finish()?.omitted.isEmpty == true)
    }

    @Test func everyNewMarkupDocumentStringIsTranslatedWithItsPlaceholdersInEveryLanguage() {
        let labels: [PreviewStrings.Key] = DocumentFrontMatterField.allCases.map(\.label)
        let keys: [PreviewStrings.Key] = labels + [.documentImageMarker, .documentOmittedImages, .documentOmittedLinkedFiles, .markupReferencesLanguageNote]
        let languages = ["tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        for key in keys {
            let source = PreviewStrings.text(key, languagePreferences: ["en"])
            for language in languages {
                let translated = PreviewStrings.text(key, languagePreferences: [language])
                #expect(!translated.isEmpty && translated != key.rawValue, "\(key.rawValue) \(language)")
                #expect(translated != source, "\(key.rawValue) \(language)")
                // Formatted keys keep exactly one object placeholder.
                #expect(translated.components(separatedBy: "%@").count == source.components(separatedBy: "%@").count, "\(key.rawValue) \(language)")
            }
        }
        #expect(PreviewStrings.text(.documentFrontMatterTitle, languagePreferences: ["en"]) == "Title:")
        #expect(PreviewStrings.text(.documentImageMarker, languagePreferences: ["en"]) == "Image: %@")
        #expect(PreviewStrings.text(.documentOmittedImages, languagePreferences: ["en"]) == "Images not loaded: %@")
        #expect(PreviewStrings.text(.documentOmittedLinkedFiles, languagePreferences: ["en"]) == "Linked files not loaded: %@")
        #expect(PreviewStrings.text(.markupReferencesLanguageNote, languagePreferences: ["en"]) == "Citation terms follow each style guide’s English conventions.")
    }
}
