import AppKit
import PreviewContracts

/// The References mode: BibTeX entries as a formatted reference list with a choice of
/// citation style (APA, MLA, Chicago author-date, IEEE). The list is selectable text drawn
/// from `SafeBibliography`, which is parsed from already-concealed text, so concealed values
/// stay concealed in every style. The chosen style is view state only: it is never persisted
/// and never changes what the file or the preferences contain. The style caveat and the note that citation
/// terms stay English are status lines of the preview host (`MarkupRendering.notices`), so this view does not
/// repeat them.
@MainActor
final class MarkupReferencesView: NSView, SafeModeContentView, PreviewSafeCopying, PreviewCopyReporting {
    var navigate: ((NativePreviewMode, NSRange) -> Void)?

    let styleControl = NSSegmentedControl()
    let textView = PreviewTextView.makeTextKit1()
    var pasteboard: NSPasteboard {
        get { textView.pasteboard }
        set { textView.pasteboard = newValue }
    }
    var tagCopyPolicy: (() -> Bool)? {
        get { textView.tagCopyPolicy }
        set { textView.tagCopyPolicy = newValue }
    }
    var copyHandler: ((PreviewCopyEvent) -> Void)? {
        get { textView.copyHandler }
        set { textView.copyHandler = newValue }
    }
    private let styleLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private(set) var selectedStyle: BibliographyStyle = .apa
    private var bibliography: SafeBibliography?
    private var lastStyle: SafeModeStyle?
    private var cache: (bibliography: SafeBibliography, style: BibliographyStyle, document: SafeMarkdownDocument?)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        styleLabel.font = .preferredFont(forTextStyle: .body)
        styleControl.segmentCount = BibliographyStyle.allCases.count
        styleControl.trackingMode = .selectOne
        styleControl.target = self
        styleControl.action = #selector(styleChanged)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.baseWritingDirection = .natural
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        for view in [styleLabel, styleControl, scrollView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            styleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            styleLabel.centerYAnchor.constraint(equalTo: styleControl.centerYAnchor),
            styleControl.leadingAnchor.constraint(equalTo: styleLabel.trailingAnchor, constant: 8),
            styleControl.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            styleControl.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: styleControl.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateLabels()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: SafeModeContentView

    func display(_ modes: SafePreviewModes, mode: NativePreviewMode, style: SafeModeStyle) {
        bibliography = modes.references
        lastStyle = style
        updateLabels()
        render()
    }

    func clear() {
        bibliography = nil
        cache = nil
        lastStyle = nil
        textView.string = ""
        textView.setAccessibilityLabel(nil)
    }

    // MARK: Rendering

    private func updateLabels() {
        styleLabel.stringValue = PreviewStrings.text(.markupReferencesStyleLabel)
        styleControl.setAccessibilityLabel(PreviewStrings.text(.markupReferencesStyleLabel))
        for (index, style) in BibliographyStyle.allCases.enumerated() {
            styleControl.setLabel(PreviewStrings.text(style.title), forSegment: index)
        }
        styleControl.selectedSegment = BibliographyStyle.allCases.firstIndex(of: selectedStyle) ?? 0
    }

    @objc private func styleChanged() {
        guard BibliographyStyle.allCases.indices.contains(styleControl.selectedSegment) else { return }
        selectedStyle = BibliographyStyle.allCases[styleControl.selectedSegment]
        render()
    }

    private func render() {
        guard let bibliography, let style = lastStyle else { return }
        let document: SafeMarkdownDocument?
        if let cache, cache.bibliography == bibliography, cache.style == selectedStyle {
            document = cache.document
        } else {
            document = BibliographyFormatter.document(bibliography, style: selectedStyle)
            cache = (bibliography, selectedStyle, document)
        }
        let typography = NativeTextTypography(style.typography, syntaxStyle: style.syntaxStyle)
        let pass = NativeTextStylePass(typography: typography, palette: style.palette, syntaxStyle: style.syntaxStyle)
        layer?.backgroundColor = style.palette.background.cgColor
        styleLabel.textColor = style.palette.foreground
        textView.backgroundColor = style.palette.background
        scrollView.backgroundColor = style.palette.background
        textView.typingAttributes = pass.baseAttributes
        let text = document?.text ?? ""
        // Replace the text only when it changed, so restyling keeps selection and scroll position.
        if textView.string != text { textView.string = text }
        textView.setAccessibilityLabel(PreviewStrings.format(.markupReferencesAccessibility,
            arguments: [Int64(bibliography.entries.count)], locale: style.locale))
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.setAttributes(pass.baseAttributes, range: NSRange(location: 0, length: storage.length))
        for decoration in document?.decorations ?? [] {
            NativeMarkdownStyling.apply(decoration, to: storage, typography: typography,
                                        palette: style.palette, syntaxStyle: style.syntaxStyle)
        }
        storage.endEditing()
    }
}
