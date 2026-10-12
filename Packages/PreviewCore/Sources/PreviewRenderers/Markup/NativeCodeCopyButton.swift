import AppKit
import PreviewContracts

/// What the margin control says to assistive technology: "Copy Swift code" for a recognized language, otherwise
/// "Copy Code Block". The language is a proper name and is never translated; only the words around it are.
enum CodeBlockCopyAccessibilityLabel {
    static func text(for language: SourceLanguageID?, locale: Locale, languagePreferences: [String]? = nil) -> String {
        guard let name = CodeLanguageName.text(for: language) else {
            return PreviewStrings.text(.markupCopyCodeBlock, languagePreferences: languagePreferences)
        }
        return PreviewStrings.format(.markupCopyLanguageCode, arguments: [name], locale: locale,
                                     languagePreferences: languagePreferences)
    }
}

/// A native control retains only one revision target and an action, never body text.
@MainActor
final class NativeCodeCopyButton: NSButton {
    private enum Symbol: String { case copy = "doc.on.doc" }
    let copyTarget: CodeBlockCopyTarget
    private let retainedAction: PreviewCommandAction

    init(target: CodeBlockCopyTarget, locale: Locale, color: NSColor,
         perform: @escaping @MainActor (CodeBlockCopyTarget) -> Bool) {
        copyTarget = target
        retainedAction = PreviewCommandAction { _ = perform(target) }
        super.init(frame: .zero)
        title = ""
        isBordered = false
        imagePosition = .imageOnly
        keyEquivalent = ""
        image = NSImage(systemSymbolName: Symbol.copy.rawValue, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        self.target = retainedAction
        action = #selector(PreviewCommandAction.run(_:))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        update(locale: locale, color: color)
    }

    required init?(coder: NSCoder) { nil }
    override var alignmentRectInsets: NSEdgeInsets { .init(top: 0, left: 0, bottom: 0, right: 0) }

    func update(locale: Locale, color: NSColor) {
        contentTintColor = color
        toolTip = PreviewStrings.text(.markupCopyCodeBlockHelp)
        setAccessibilityHelp(toolTip)
        setAccessibilityLabel(CodeBlockCopyAccessibilityLabel.text(for: copyTarget.block.language, locale: locale))
    }

    override func keyDown(with event: NSEvent) {
        if PreviewKeyPolicy.reservesForHost(keyCode: event.keyCode) {
            nextResponder?.keyDown(with: event)
        } else if [PreviewKeyCode.returnKey, PreviewKeyCode.keypadEnter].contains(event.keyCode),
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            performClick(nil)
        } else { super.keyDown(with: event) }
    }
}
