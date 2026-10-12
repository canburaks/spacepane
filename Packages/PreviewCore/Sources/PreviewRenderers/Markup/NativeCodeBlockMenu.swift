import AppKit
import PreviewContracts

enum CodeBlockCopyMenuTitle {
    static func text(for language: SourceLanguageID?, locale: Locale,
                     languagePreferences: [String]? = nil) -> String {
        guard let language, SourceLanguageID.all.contains(language) else {
            return PreviewStrings.text(.markupCopyCodeBlock, languagePreferences: languagePreferences)
        }
        return PreviewStrings.format(.markupCopyCodeBlockLanguage, arguments: [language.rawValue],
                                     locale: locale, languagePreferences: languagePreferences)
    }
}

extension NativePreviewView {
    /// A menu retains only a revision target and a weak facade, never a copy of document text.
    func codeBlockCopyMenuItem(at characterIndex: Int,
                              languagePreferences: [String]? = nil) -> NSMenuItem? {
        guard let target = codeBlockCopyTarget(at: characterIndex) else { return nil }
        let action = PreviewCommandAction { [weak self] in _ = self?.copyCodeBlock(target) }
        let item = NSMenuItem(title: CodeBlockCopyMenuTitle.text(for: target.block.language,
                             locale: presentationLocale, languagePreferences: languagePreferences),
                             action: #selector(PreviewCommandAction.run(_:)), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        return item
    }
}
