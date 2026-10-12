import AppKit
import PreviewContracts

/// The one selectable TextKit 1 stack for Source, Rendered and Invisibles. It owns only safe text,
/// styling and reading geometry; the facade owns mode choice, commands and request/resource lifetime.
@MainActor
final class PreviewTextContentView: NSView {
    /// Injected only by a measuring host; nil performs no clock or signpost work.
    var stageObserver: PreviewStageObserver?

    let textView = PreviewTextView.makeTextKit1()
    let scrollView = NSScrollView()
    lazy var lineNumberGutter = LogicalLineNumberGutter(scrollView: scrollView, textView: textView)
    private var gutterWidthConstraint: NSLayoutConstraint?
    private var lineNumbersPermitted = false
    private var density = PreviewChrome.Density.regular
    private var syntax = TextSyntax.plain
    private var syntaxTokens: [JSONSyntaxToken] = []
    private var markdownDecorations: [MarkdownDecoration] = []
    private var codeBlocks: [MarkupCodeBlock] = []
    private var codeBlockSyntaxTokens: [JSONSyntaxToken] = []
    var codeBlockTokenBuilder: (@MainActor (String, [MarkupCodeBlock]) -> [JSONSyntaxToken]) = {
        CodeBlockSyntaxTokens.tokens(in: $0, blocks: $1)
    }
    private var codeBlockCopyRevision = UUID()
    private var codeBlockMarginIndex = CodeBlockMarginIndex([], textLength: 0)
    private var codeCopyButtons: [NativeCodeCopyButton] = []
    private var copyControlsAreActive = true
    private var copyControlsAreRendered = false
    private var copyControlLocale = Locale.current
    private var copyControlColor = NSColor.textColor
    var performCodeBlockCopy: (@MainActor (CodeBlockCopyTarget) -> Bool)?
    private var invisibleMarkerRanges: [NSRange] = []
    private var wrapsLines = true
    private var readingLayout: ReadingLayout?
    private var documentNeedsSizing = true
    private var measuredViewport: NSSize?
    /// Stops clip-view tiling from re-entering document measurement.
    private var isConfiguringDocumentSize = false
    /// Gutter changes need the facade's header/content constraints resolved before text is measured.
    var onGutterWidthChange: (() -> Void)?
    /// Called after the reading viewport scrolled or resized; the Contents rail follows the reader through it.
    var onViewportChange: (() -> Void)?

    struct Replacement {
        let readingPosition: (selection: NSRange, origin: NSPoint)?
        let resetsReadingPosition: Bool
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.textContainerInset = NSSize(width: PreviewChrome.inset, height: PreviewChrome.inset)
        // Representables start at zero size. Do not wrap/measure before host constraints resolve.
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                      height: CGFloat.greatestFiniteMagnitude)
        prepareTextAccessibility()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(copyViewportChanged),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        lineNumberGutter.translatesAutoresizingMaskIntoConstraints = false
        lineNumberGutter.isHidden = true
        let gutterWidth = lineNumberGutter.widthAnchor.constraint(equalToConstant: 0)
        // Zero-sized representables and extremely narrow hosts can shrink the gutter safely.
        gutterWidth.priority = .defaultHigh
        gutterWidthConstraint = gutterWidth
        addSubview(lineNumberGutter)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            lineNumberGutter.leadingAnchor.constraint(equalTo: leadingAnchor),
            lineNumberGutter.topAnchor.constraint(equalTo: scrollView.topAnchor),
            lineNumberGutter.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            gutterWidth,
            lineNumberGutter.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
            scrollView.leadingAnchor.constraint(equalTo: lineNumberGutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }
    isolated deinit { NotificationCenter.default.removeObserver(self, name: nil, object: scrollView.contentView) }

    override func layout() {
        super.layout()
        configureDocumentSize()
    }

    func prepareTextAccessibility() {
        textView.baseWritingDirection = .natural
        textView.setAccessibilityLabel(PreviewStrings.text(.selectableContent))
        textView.setAccessibilityHelp(PreviewStrings.text(.contentHelp))
    }

    func setContentHidden(_ hidden: Bool) {
        if hidden {
            codeBlocks = []
            codeBlockSyntaxTokens.removeAll(keepingCapacity: false)
            codeBlockMarginIndex = CodeBlockMarginIndex([], textLength: 0)
            invalidateCodeBlockCopyTargets()
        }
        isHidden = hidden
        scrollView.isHidden = hidden
        textView.isHidden = hidden
    }

    /// A hidden replacement forgets stale safe source before a different mode can reveal it.
    func clear(resetsReadingPosition: Bool = false) {
        hideLineNumbers()
        codeBlocks = []
        codeBlockSyntaxTokens.removeAll(keepingCapacity: false)
        codeBlockMarginIndex = CodeBlockMarginIndex([], textLength: 0)
        invalidateCodeBlockCopyTargets()
        setStoredContent("")
        syntaxTokens.removeAll(keepingCapacity: false)
        syntax = .plain
        markdownDecorations = []
        invisibleMarkerRanges = []
        setLineContent("")
        if resetsReadingPosition {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            scrollView.contentView.scroll(to: .zero)
        }
    }

    func hideLineNumbers() {
        lineNumbersPermitted = false
        lineNumberGutter.isHidden = true
        gutterWidthConstraint?.constant = 0
    }

    /// Rotation invalidates retained actions without copying or changing safe text.
    func invalidateCodeBlockCopyTargets() {
        codeBlockCopyRevision = UUID()
        removeCodeCopyButtons()
    }

    func setCodeBlockCopyControlsActive(_ active: Bool) {
        copyControlsAreActive = active
        refreshCodeBlockCopyControls()
    }

    @objc nonisolated private func copyViewportChanged() {
        Task { @MainActor [weak self] in
            self?.refreshCodeBlockCopyControls()
            self?.onViewportChange?()
        }
    }

    private func removeCodeCopyButtons(except kept: [NativeCodeCopyButton] = []) {
        for button in codeCopyButtons where !kept.contains(where: { $0 === button }) {
            if window?.firstResponder === button {
                window?.makeFirstResponder(textView.isHiddenOrHasHiddenAncestor ? nil : textView)
            }
            button.removeFromSuperview()
        }
        codeCopyButtons = kept
    }

    /// Only indexed visible bodies reach native geometry; scrolling never ensures whole-container layout.
    func refreshCodeBlockCopyControls() {
        guard copyControlsAreActive, copyControlsAreRendered, !isHiddenOrHasHiddenAncestor,
              let perform = performCodeBlockCopy, let manager = textView.layoutManager,
              let container = textView.textContainer, let storage = textView.textStorage else {
            removeCodeCopyButtons(); return
        }
        let viewport = textView.visibleRect, origin = textView.textContainerOrigin
        let glyphs = manager.glyphRange(forBoundingRect: viewport.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let column = NSRect(x: origin.x, y: viewport.minY, width: container.containerSize.width, height: viewport.height)
        var kept: [NativeCodeCopyButton] = []
        for index in codeBlockMarginIndex.candidates(overlapping: characters) {
            guard codeBlocks.indices.contains(index) else { continue }
            let block = codeBlocks[index]
            guard let range = validCodeBlockRange(block),
                  let paragraph = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
                  let card = paragraph.textBlocks.first(where: { $0 is NativeCodeTextBlock }) else { continue }
            let glyph = manager.glyphIndexForCharacter(at: range.location)
            guard glyph < manager.numberOfGlyphs else { continue }
            let cardBounds = manager.boundsRect(for: card, at: glyph, effectiveRange: nil).offsetBy(dx: origin.x, dy: origin.y)
            // Native bounds include the card's padding/background; reserve both it and the reading column.
            let exclusion = NSRect(x: min(column.minX, cardBounds.minX), y: viewport.minY,
                width: max(column.maxX, cardBounds.maxX) - min(column.minX, cardBounds.minX), height: viewport.height)
            guard let frame = CodeBlockMarginPlacement.frame(card: cardBounds, column: exclusion, viewport: viewport,
                trailingOnLeft: LineNumberPlacement(resolvedFor: lineNumberGutter).isRightToLeft) else { continue }
            let target = CodeBlockCopyTarget(revision: codeBlockCopyRevision, block: block)
            let button = codeCopyButtons.first(where: { $0.copyTarget == target })
                ?? NativeCodeCopyButton(target: target, locale: copyControlLocale, color: copyControlColor, perform: perform)
            button.update(locale: copyControlLocale, color: copyControlColor)
            button.frame = convert(frame, from: textView)
            if button.superview == nil { addSubview(button) }
            kept.append(button)
        }
        removeCodeCopyButtons(except: kept)
    }

    func codeBlockCopyTarget(at characterIndex: Int) -> CodeBlockCopyTarget? {
        guard characterIndex >= 0, characterIndex != NSNotFound else { return nil }
        for block in codeBlocks {
            guard let range = validCodeBlockRange(block), characterIndex >= range.location,
                  characterIndex < range.location + range.length else { continue }
            return .init(revision: codeBlockCopyRevision, block: block)
        }
        return nil
    }

    func currentCodeBlockRange(for target: CodeBlockCopyTarget) -> NSRange? {
        guard target.revision == codeBlockCopyRevision, codeBlocks.contains(target.block) else { return nil }
        return validCodeBlockRange(target.block)
    }

    private func validCodeBlockRange(_ block: MarkupCodeBlock) -> NSRange? {
        let range = block.range
        let length = textView.textStorage?.length ?? 0
        guard range.location >= 0, range.location != NSNotFound, range.location <= length,
              range.length > 0, range.length <= length - range.location else { return nil }
        return range
    }

    /// Resize only cached gutter geometry; source, style, selection and preferences stay intact.
    func setDensity(_ density: PreviewChrome.Density) {
        guard self.density != density else { return }
        self.density = density
        let selectedRanges = textView.selectedRanges
        let origin = scrollView.contentView.bounds.origin
        guard updateGutterGeometry() else { return }
        configureDocumentSize()
        textView.selectedRanges = selectedRanges
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @discardableResult
    private func updateGutterGeometry() -> Bool {
        let showsGutter = lineNumbersPermitted && density == .regular && !isHidden && !scrollView.isHidden
            && lineNumberGutter.lineIndex.count > 0
        lineNumberGutter.isHidden = !showsGutter
        let gutterWidth = showsGutter ? lineNumberGutter.requiredWidth : 0
        guard gutterWidthConstraint?.constant != gutterWidth else { return false }
        gutterWidthConstraint?.constant = gutterWidth
        documentNeedsSizing = true
        needsLayout = true
        if let onGutterWidthChange { onGutterWidthChange() } else { layoutSubtreeIfNeeded() }
        return true
    }

    /// Exact UTF-16 comparison preserves a replacement's spelling even when Swift String equality folds it.
    func replaceContent(_ content: String, syntax newSyntax: TextSyntax, language: SourceLanguageID?,
                        decorations: [MarkdownDecoration], codeBlocks newCodeBlocks: [MarkupCodeBlock] = [],
                        markerRanges: [NSRange],
                        hasDisplayableContent: Bool, keepsReadingPosition: Bool,
                        resetsContentState: Bool) -> Replacement {
        markdownDecorations = decorations
        invisibleMarkerRanges = markerRanges
        let contentChanged = !textView.string.utf16.elementsEqual(content.utf16)
        let codeBlocksChanged = codeBlocks != newCodeBlocks
        let rebuildMarginIndex = contentChanged || codeBlocksChanged || resetsContentState
        if rebuildMarginIndex { invalidateCodeBlockCopyTargets() }
        codeBlocks = newCodeBlocks
        if contentChanged || !hasDisplayableContent { setLineContent(content) }
        if contentChanged || syntax != newSyntax || codeBlocksChanged {
            let interval = stageObserver?.begin(.tokens)
            if contentChanged || syntax != newSyntax {
                syntaxTokens = SourceSyntaxTokens.tokens(in: content, syntax: newSyntax, language: language)
                syntax = newSyntax
            }
            if contentChanged || codeBlocksChanged {
                codeBlockSyntaxTokens = codeBlocks.isEmpty ? [] : codeBlockTokenBuilder(content, codeBlocks)
            }
            if let interval { interval.finish(count: syntaxTokens.count + codeBlockSyntaxTokens.count) }
        }
        let readingPosition = keepsReadingPosition && contentChanged
            ? (selection: textView.selectedRange(), origin: scrollView.contentView.bounds.origin) : nil
        if contentChanged { setStoredContent(content) }
        if rebuildMarginIndex { codeBlockMarginIndex = CodeBlockMarginIndex(codeBlocks, textLength: textView.textStorage?.length ?? 0) }
        return Replacement(readingPosition: readingPosition,
                           resetsReadingPosition: contentChanged || resetsContentState)
    }

    /// Measures the actual index construction; its work unit is a logical line in the concealed display text.
    private func setLineContent(_ content: String) {
        let interval = stageObserver?.begin(.lineIndex)
        lineNumberGutter.setContent(content)
        if let interval { interval.finish(count: lineNumberGutter.lineIndex.count) }
    }

    /// Measures only a real storage assignment, including a hidden generation's clear. The work count is the
    /// resulting storage's UTF-16 length; no count traversal runs on the ordinary, unmeasured path.
    private func setStoredContent(_ content: String) {
        let interval = stageObserver?.begin(.storage)
        textView.string = content
        if let interval { interval.finish(count: textView.textStorage?.length ?? 0) }
    }

    /// Styling resolves the new document size before the old reading position is clamped to it.
    func finishReplacement(_ replacement: Replacement) {
        if let readingPosition = replacement.readingPosition {
            restoreReadingPosition(readingPosition.selection, origin: readingPosition.origin)
        } else if replacement.resetsReadingPosition {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func restoreReadingPosition(_ selection: NSRange, origin: NSPoint) {
        let length = (textView.string as NSString).length
        let location = min(selection.location, length)
        textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        let maximumY = max(0, textView.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: origin.x, y: min(max(origin.y, 0), maximumY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func apply(typography: PreviewTypography, resolved: NativeTextTypography, palette: NativeTextPalette,
               syntaxStyle: PreviewSyntaxStyle, showsLineNumbers: Bool, isRendered: Bool = false, locale: Locale = .current) {
        copyControlsAreRendered = isRendered
        copyControlLocale = locale
        copyControlColor = palette.muted
        let interval = stageObserver?.begin(.styling)
        let selectedRanges = textView.selectedRanges
        let origin = scrollView.contentView.bounds.origin
        let stylePass = NativeTextStylePass(typography: resolved, palette: palette, syntaxStyle: syntaxStyle)
        readingLayout = isRendered ? ReadingLayout(typography: resolved) : nil
        var attributes = stylePass.baseAttributes
        if let readingLayout {
            attributes[.font] = readingLayout.font
            attributes[.paragraphStyle] = readingLayout.paragraphStyle
        }
        textView.backgroundColor = palette.background
        scrollView.backgroundColor = palette.background
        textView.typingAttributes = attributes
        if let storage = textView.textStorage {
            storage.beginEditing()
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            for token in syntaxTokens {
                storage.setAttributes(stylePass.attributes(for: token.role), range: token.range)
            }
            for decoration in markdownDecorations {
                NativeMarkdownStyling.apply(decoration, to: storage, typography: resolved, palette: palette, syntaxStyle: syntaxStyle)
            }
            if isRendered {
                NativeMarkdownStyling.applyCodeBlocks(codeBlocks, to: storage, palette: palette)
                NativeCodeBlockStyling.apply(codeBlockSyntaxTokens, to: storage, stylePass: stylePass)
            }
            if !invisibleMarkerRanges.isEmpty {
                let markerAttributes = invisibleMarkerAttributes(stylePass.baseAttributes, typography: resolved,
                                                                 palette: palette, syntaxStyle: syntaxStyle)
                for range in invisibleMarkerRanges where range.location >= 0 && NSMaxRange(range) <= storage.length {
                    storage.addAttributes(markerAttributes, range: range)
                }
            }
            storage.endEditing()
        }
        lineNumberGutter.apply(font: resolved.font, palette: palette)
        // Styling covers attributes and the gutter palette; layout is measured separately below, including when
        // resolving the changed gutter width reenters the facade's layout path.
        if let interval { interval.finish(count: textView.textStorage?.length ?? 0) }
        lineNumbersPermitted = !isRendered && showsLineNumbers
        wrapsLines = isRendered || typography.wrapsLines
        documentNeedsSizing = true
        configureWrapping(wrapsLines)
        updateGutterGeometry()
        configureDocumentSize()
        textView.selectedRanges = selectedRanges
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Markers are app-generated stand-ins, not source. Weight and, without color, underline keep them
    /// distinct for readers who cannot rely on hue; the angle brackets remain a plain-text cue.
    private func invisibleMarkerAttributes(_ base: [NSAttributedString.Key: Any], typography: NativeTextTypography,
                                           palette: NativeTextPalette, syntaxStyle: PreviewSyntaxStyle) -> [NSAttributedString.Key: Any] {
        var attributes = base
        attributes[.foregroundColor] = palette.invisibleMarkerColor(style: syntaxStyle)
        let bold = NSFontManager.shared.convert(typography.font, toHaveTrait: .boldFontMask)
        if NSFontManager.shared.traits(of: bold).contains(.boldFontMask) { attributes[.font] = bold }
        if !syntaxStyle.usesColor { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    private func configureWrapping(_ wraps: Bool) {
        scrollView.hasHorizontalScroller = !wraps
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = !wraps
        textView.autoresizingMask = wraps ? [.width] : []
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    func configureDocumentSize() {
        guard !isConfiguringDocumentSize else { return }
        isConfiguringDocumentSize = true
        defer {
            isConfiguringDocumentSize = false
            refreshCodeBlockCopyControls()
        }
        guard !scrollView.isHidden else { return }
        guard let container = textView.textContainer, let manager = textView.layoutManager else { return }
        let wraps = wrapsLines
        func measure(_ viewport: NSSize) {
            guard hasUsableViewport(viewport) else {
                container.widthTracksTextView = false
                container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                height: CGFloat.greatestFiniteMagnitude)
                return
            }
            guard documentNeedsSizing || measuredViewport != viewport else { return }
            let interval = stageObserver?.begin(.layout)
            documentNeedsSizing = false
            measuredViewport = viewport
            container.widthTracksTextView = wraps
            let size = NSSize(width: wraps ? max(1, viewport.width - textView.textContainerInset.width * 2) : CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
            if container.containerSize != size { container.containerSize = size }
            if wraps { textView.frame.size.width = max(viewport.width, 1) }
            manager.ensureLayout(for: container)
            let used = manager.usedRect(for: container)
            let contentHeight = max(used.maxY, manager.extraLineFragmentRect.maxY)
            textView.setFrameSize(NSSize(
                width: wraps ? max(viewport.width, 1) : max(viewport.width, used.maxX + textView.textContainerInset.width * 2),
                height: max(viewport.height, contentHeight + textView.textContainerInset.height * 2)
            ))
            lineNumberGutter.needsDisplay = true
            // Read the already-laid-out glyph count only for an injected observer. Cache hits return before begin.
            if let interval { interval.finish(count: manager.numberOfGlyphs) }
        }
        var viewport = scrollView.contentSize
        updateReadingInset(viewportWidth: viewport.width)
        if wraps, hasUsableViewport(viewport), documentNeedsSizing || measuredViewport != viewport,
           reserveVerticalScrollerForCertainOverflow(viewport: viewport, manager: manager) {
            viewport = scrollView.contentSize
            updateReadingInset(viewportWidth: viewport.width)
        }
        measure(viewport)
        // Setting the document height can reveal a legacy scroller and narrow the clip after the width
        // was chosen. Overlay scrollers do not change the width, and a scroller reserved beforehand
        // already matches this viewport, so the comparison performs no second layout.
        guard wraps else { return }
        let resolved = scrollView.contentSize
        guard resolved.width + 0.5 < viewport.width else { return }
        documentNeedsSizing = true
        measuredViewport = nil
        updateReadingInset(viewportWidth: resolved.width)
        measure(resolved)
    }

    private func updateReadingInset(viewportWidth: CGFloat) {
        let inset = readingLayout?.horizontalInset(viewportWidth: viewportWidth) ?? PreviewChrome.inset
        if textView.textContainerInset.width != inset {
            textView.textContainerInset.width = inset
            documentNeedsSizing = true
        }
    }

    private func hasUsableViewport(_ viewport: NSSize) -> Bool {
        viewport.width > textView.textContainerInset.width * 2 && viewport.height > 0
    }

    /// A legacy vertical scroller appears only after the document outgrows the viewport and then narrows
    /// the clip view, which re-wraps text that was just laid out. When a lower bound on the wrapped height
    /// already overflows, a document of that height makes the scroll view reserve the scroller before the
    /// single measuring layout. Overlay scrollers never change the width, and documents that may fit keep
    /// the unchanged path. The exact height is still measured afterward, so the bound only affects speed.
    private func reserveVerticalScrollerForCertainOverflow(viewport: NSSize, manager: NSLayoutManager) -> Bool {
        // The scroller is already accounted for, or does not take layout width, when the content size is unchanged.
        let withScroller = NSScrollView.contentSize(forFrameSize: scrollView.frame.size, horizontalScrollerClass: nil,
            verticalScrollerClass: NSScroller.self, borderType: scrollView.borderType,
            controlSize: scrollView.verticalScroller?.controlSize ?? .regular, scrollerStyle: scrollView.scrollerStyle)
        guard scrollView.hasVerticalScroller, withScroller.width < viewport.width else { return false }
        let font = (textView.typingAttributes[.font] as? NSFont) ?? textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let lineHeight = floor(manager.defaultLineHeight(for: font))
        guard lineHeight > 0 else { return false }
        // Every logical line takes at least one fragment, and a fragment holds at most as many characters as fit
        // at a quarter of the point size (narrower than any ordinary advance, even with tightened spacing).
        let spacing = (textView.typingAttributes[.kern] as? CGFloat) ?? 0
        let narrowestAdvance = max(1, font.pointSize * 0.25 + spacing)
        let usableWidth = viewport.width - textView.textContainerInset.width * 2
            - (textView.textContainer?.lineFragmentPadding ?? 0) * 2
        let charactersPerFragment = max(1, usableWidth / narrowestAdvance)
        let lines = lineNumberGutter.lineIndex
        var fragments = 0
        for (position, start) in lines.starts.enumerated() {
            let end = position + 1 < lines.starts.count ? lines.starts[position + 1] : lines.utf16Length
            fragments += max(1, Int((CGFloat(end - start) / charactersPerFragment).rounded(.up)))
        }
        let minimumHeight = CGFloat(fragments) * lineHeight + textView.textContainerInset.height * 2
        guard minimumHeight > viewport.height else { return false }
        textView.setFrameSize(NSSize(width: textView.frame.width, height: minimumHeight))
        scrollView.tile()
        return true
    }
}
