import AppKit
import PreviewContracts

/// Applies inert markup decorations to already-concealed rendered text. Decorations only
/// change fonts, colors, glyph attributes and paragraph layout; they never add links,
/// attachments that load resources, or actions. Decorations arrive with block and paragraph
/// styles first, so inline styles compose on the fonts those set.
enum NativeMarkdownStyling {
    /// One em of horizontal layout, used for list nesting and screenplay indentation.
    @MainActor
    private static func indentUnit(_ typography: NativeTextTypography) -> CGFloat { typography.font.pointSize * 1.5 }

    @MainActor
    static func apply(_ decoration: MarkdownDecoration, to storage: NSTextStorage,
                      typography: NativeTextTypography, palette: NativeTextPalette, syntaxStyle: PreviewSyntaxStyle) {
        let range = decoration.range
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= storage.length else { return }
        let current = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) ?? typography.font
        func color(_ role: PreviewSyntaxRole) -> NSColor { palette.color(for: role, style: syntaxStyle) }
        func set(_ font: NSFont? = nil, _ role: PreviewSyntaxRole? = nil) {
            var attributes: [NSAttributedString.Key: Any] = [:]
            if let font { attributes[.font] = font }
            if let role { attributes[.foregroundColor] = color(role) }
            storage.addAttributes(attributes, range: range)
        }
        func body(_ font: NSFont) {
            storage.addAttributes([.font: font, .foregroundColor: palette.foreground], range: range)
        }
        func traits(_ mask: NSFontTraitMask) -> NSFont { NSFontManager.shared.convert(current, toHaveTrait: mask) }
        let codeFont = typography.font

        switch decoration.style {
        case .heading(let level):
            // A modular scale from the configured size, in the system face (decision D2), with space above.
            let base = typography.font.pointSize
            set(NSFont.systemFont(ofSize: MarkupHeadingScale.pointSize(level: level, base: base), weight: .bold), .heading)
            alter(storage, range, typography) {
                $0.paragraphSpacingBefore = MarkupHeadingScale.spacingBefore(level: level, base: base)
            }
        case .bold: body(traits(.boldFontMask))
        case .italic: body(traits(.italicFontMask))
        case .tableHeader: set(traits(.boldFontMask), .literal)
        case .code:
            set(codeFont, .string)
            addChip(to: storage, range: range, palette: palette, syntaxStyle: syntaxStyle)
        case .codeBlock: set(codeFont, .string)
        case .diagramSource: set(codeFont, .tag)
        case .quote:
            // Ordinary prose retains the base body ink; headings and later inline styles keep their own ink.
            alter(storage, range, typography) { style in
                // An alert's bar, whichever decoration was applied first, stands in for the plain quote bar.
                if style.textBlocks.contains(where: { $0 is NativeAlertTextBlock }) { return }
                style.textBlocks = style.textBlocks.filter { !($0 is NativeQuoteTextBlock) }
                    + [NativeQuoteTextBlock.make(fontSize: typography.font.pointSize, palette: palette,
                                                direction: style.baseWritingDirection)]
            }
        case .alertBar(let kind):
            // The bar takes its ink from the kind's palette role, so every scheme keeps its measured contrast.
            let ink = color(kind.syntaxRole)
            alter(storage, range, typography) { style in
                style.textBlocks = style.textBlocks.filter { !($0 is NativeQuoteTextBlock) && !($0 is NativeAlertTextBlock) }
                    + [NativeAlertTextBlock.make(fontSize: typography.font.pointSize, ink: ink,
                                                direction: style.baseWritingDirection)]
            }
        case .table(let columns, let hasHeader):
            applyTable(columns: columns, hasHeader: hasHeader, range: range, to: storage, typography: typography)
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            set(nil, .comment)
        case .math, .mathBlock:
            set(mathFont(size: typography.font.pointSize, fallback: current), .number)
            if decoration.style == .mathBlock { alter(storage, range, typography) { $0.alignment = .center } }
        case .alertTitle(let kind):
            set(traits(.boldFontMask), kind.syntaxRole)
        case .frontMatterBlock:
            storage.addAttribute(.backgroundColor, value: palette.foreground.withAlphaComponent(0.07), range: range)
        case .frontMatterKey: set(traits(.boldFontMask), .key)
        case .footnoteMark: set(nil, .key)
        case .footnoteLabel: set(traits(.boldFontMask), .key)
        case .taskMarker(let done): set(nil, done ? .addition : .comment)
        case .rule: applyRule(range: range, to: storage, typography: typography, palette: palette)
        case .dimmed: set(nil, .comment)
        case .definitionTerm: set(traits(.boldFontMask), nil)
        case .listItem(let depth, let markerLength):
            let unit = indentUnit(typography)
            let hanging = hangingWidth(markerLength, typography)
            alter(storage, range, typography) {
                $0.firstLineHeadIndent = CGFloat(depth) * unit
                $0.headIndent = CGFloat(depth) * unit + hanging
            }
        case .listContinuation(let depth, let markerLength):
            let unit = indentUnit(typography)
            let hanging = hangingWidth(markerLength, typography)
            alter(storage, range, typography) {
                $0.firstLineHeadIndent = CGFloat(depth) * unit + hanging
                $0.headIndent = CGFloat(depth) * unit + hanging
            }
        case .indent(let levels):
            let width = CGFloat(levels) * indentUnit(typography)
            alter(storage, range, typography) {
                $0.firstLineHeadIndent += width
                $0.headIndent += width
            }
        case .centered: alter(storage, range, typography) { $0.alignment = .center }
        case .trailing: alter(storage, range, typography) { $0.alignment = .right }
        case .rightToLeft:
            // Natural alignment follows the paragraph's own direction: right-to-left text sits on the right.
            alter(storage, range, typography) {
                $0.baseWritingDirection = .rightToLeft
                $0.alignment = .natural
                $0.textBlocks = $0.textBlocks.map { block -> NSTextBlock in
                    if let quote = block as? NativeQuoteTextBlock { return quote.following(.rightToLeft) }
                    if let alert = block as? NativeAlertTextBlock { return alert.following(.rightToLeft) }
                    return block
                }
            }
        }
    }

    /// A subtle tint behind an inline code span, unless no tint keeps the code ink readable. The chip is an attribute
    /// of the span, so it never changes the text; the card pass removes it again inside code bodies, which already
    /// have a card.
    @MainActor
    private static func addChip(to storage: NSTextStorage, range: NSRange, palette: NativeTextPalette,
                                syntaxStyle: PreviewSyntaxStyle) {
        let tint = MarkupSurface.chipTint(
            background: MarkupSurface.rgb(of: palette.background),
            foreground: MarkupSurface.rgb(of: palette.foreground),
            ink: MarkupSurface.rgb(of: palette.color(for: .string, style: syntaxStyle)))
        guard tint > 0 else { return }
        storage.addAttribute(.backgroundColor, value: palette.foreground.withAlphaComponent(CGFloat(tint)), range: range)
    }

    /// A thematic break is a line along the bottom of an otherwise empty paragraph. The characters the renderer wrote
    /// stay in the text, so copying and reading order are as before, but they take no ink and almost no height: the
    /// paragraph's border is the rule.
    @MainActor
    private static func applyRule(range: NSRange, to storage: NSTextStorage, typography: NativeTextTypography,
                                  palette: NativeTextPalette) {
        // The paragraph's line feed is covered too, or it would keep the line as tall as the body text.
        var covered = range
        if NSMaxRange(range) < storage.length, (storage.string as NSString).character(at: NSMaxRange(range)) == 10 {
            covered.length += 1
        }
        storage.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 2)], range: covered)
        let line = NativeRuleTextBlock.make(fontSize: typography.font.pointSize, ink: palette.muted)
        alter(storage, covered, typography) { style in
            style.textBlocks = style.textBlocks.filter { !($0 is NativeRuleTextBlock) } + [line]
        }
    }

    /// The width of a list marker and its space, from the advance of a digit in the current face.
    @MainActor
    private static func hangingWidth(_ markerLength: Int, _ typography: NativeTextTypography) -> CGFloat {
        let digit = ("0" as NSString).size(withAttributes: [.font: typography.font]).width
        return CGFloat(max(markerLength, 1)) * max(digit, typography.font.pointSize * 0.5)
    }

    /// A serif italic face for mathematics, falling back to an italic of the current font.
    @MainActor
    private static func mathFont(size: CGFloat, fallback: NSFont) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        if let descriptor = base.fontDescriptor.withDesign(.serif)?.withSymbolicTraits(.italic),
           let font = NSFont(descriptor: descriptor, size: size) { return font }
        return NSFontManager.shared.convert(fallback, toHaveTrait: .italicFontMask)
    }

    /// Edits a copy of each paragraph style in `range`, so a run spanning several paragraphs
    /// keeps the indentation and direction the earlier decorations gave them.
    @MainActor
    static func alter(_ storage: NSTextStorage, _ range: NSRange, _ typography: NativeTextTypography,
                      _ change: (NSMutableParagraphStyle) -> Void) {
        var updates: [(NSRange, NSParagraphStyle)] = []
        storage.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, subrange, _ in
            let style = ((value as? NSParagraphStyle) ?? typography.paragraphStyle).mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            change(style)
            updates.append((subrange, style))
        }
        for (subrange, style) in updates { storage.addAttribute(.paragraphStyle, value: style, range: subrange) }
    }
}
