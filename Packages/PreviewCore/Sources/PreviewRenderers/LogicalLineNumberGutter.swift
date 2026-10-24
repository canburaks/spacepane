import AppKit

/// A separate gutter keeps numbers out of selection, find, text storage and copied content.
/// It caches only line starts, and draws first fragments of visible logical lines.
@MainActor
final class LogicalLineNumberGutter: NSView {
    struct Label: Equatable {
        let number: Int
        /// Baseline in text-view coordinates, including its text container origin.
        let baseline: CGFloat
    }

    private(set) var lineIndex = LogicalLineIndex("")
    private(set) var requiredWidth: CGFloat = 0
    var onDoubleClick: (() -> Void)?
    private weak var textView: NSTextView?
    private var font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private var foreground = NSColor.textColor
    private var background = NSColor.textBackgroundColor
    private var rule = NSColor.separatorColor
    private let horizontalPadding = PreviewChrome.gap

    /// Where the numbers and the hairline sit for the layout direction the gutter is placed in (Q-161). The gutter is
    /// pinned to its superview's leading edge, so under a right-to-left layout it moves to the right of the text and
    /// the numbers align left, toward the text, with the hairline on the gutter's left edge.
    var placement: LineNumberPlacement { LineNumberPlacement(resolvedFor: self) }

    /// How the numbers are aligned inside the gutter: toward the text.
    var numberAlignment: NSTextAlignment { placement.alignment }

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.ruler)
        setAccessibilityChildren([])
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    func setContent(_ text: String) {
        lineIndex = LogicalLineIndex(text)
        setAccessibilityValue(NSNumber(value: lineIndex.count))
        updateThickness()
        needsDisplay = true
    }

    /// Line numbers are the quiet tier: muted ink, and one hairline between them and the text. Where the scheme's
    /// body ink leaves no lightness headroom (`mutedUsesSizeCue`) the numbers also draw at the muted size, so size
    /// carries the hierarchy the ink cannot.
    func apply(font: NSFont, palette: NativeTextPalette) {
        if palette.mutedUsesSizeCue, font.pointSize > PreviewChrome.mutedPointSize {
            self.font = NSFontManager.shared.convert(font, toSize: PreviewChrome.mutedPointSize)
        } else {
            self.font = font
        }
        foreground = palette.muted
        background = palette.background
        rule = palette.hairline
        toolTip = PreviewStrings.text(.lineNumbers)
        setAccessibilityLabel(PreviewStrings.text(.lineNumbers))
        setAccessibilityHelp(PreviewStrings.text(.lineNumbersHint))
        updateThickness()
        needsDisplay = true
    }

    private func updateThickness() {
        // Measure all digits: user-selected fonts can have proportional numeral widths.
        let digitWidth = (0...9).map { (String($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let digits = String(max(1, lineIndex.count)).count
        let width = ceil(digitWidth * CGFloat(digits) + horizontalPadding * 2)
        requiredWidth = width
    }

    @objc private func viewportChanged() { needsDisplay = true }

    /// Only visible glyphs determine candidates; soft wraps never introduce another number.
    func visibleLabels(in textView: NSTextView) -> [Label] {
        guard !lineIndex.starts.isEmpty, let manager = textView.layoutManager,
              let container = textView.textContainer else { return [] }
        let origin = textView.textContainerOrigin
        let visible = textView.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = manager.glyphRange(forBoundingRect: visible, in: container)
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        guard let first = lineIndex.lineIndex(containingUTF16: min(characters.location, lineIndex.utf16Length)),
              let last = lineIndex.lineIndex(containingUTF16: min(NSMaxRange(characters), lineIndex.utf16Length)) else { return [] }
        var labels: [Label] = []
        for index in first...last {
            let start = lineIndex.starts[index]
            let fragment: NSRect
            let baseline: CGFloat
            if start == lineIndex.utf16Length {
                // TextKit owns a distinct extra fragment for the final empty line.
                fragment = manager.extraLineFragmentRect
                baseline = fragment.minY + manager.defaultBaselineOffset(for: font)
            } else {
                let glyph = manager.glyphIndexForCharacter(at: start)
                guard glyph < manager.numberOfGlyphs else { continue }
                fragment = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                baseline = fragment.minY + manager.location(forGlyphAt: glyph).y
            }
            guard fragment.height > 0, fragment.maxY > visible.minY, fragment.minY < visible.maxY else { continue }
            labels.append(Label(number: index + 1, baseline: baseline + origin.y))
        }
        return labels
    }

    /// One device pixel, so the rule stays a hairline on every display.
    private var ruleWidth: CGFloat { 1 / max(window?.backingScaleFactor ?? 1, 1) }

    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        dirtyRect.fill()
        let placement = self.placement
        rule.setFill()
        placement.ruleFrame(in: bounds, thickness: ruleWidth, within: dirtyRect).fill()
        guard let textView, let manager = textView.layoutManager else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
        let baselineOffset = manager.defaultBaselineOffset(for: font)
        for label in visibleLabels(in: textView) {
            let number = String(label.number) as NSString
            let size = number.size(withAttributes: attributes)
            let baseline = convert(NSPoint(x: 0, y: label.baseline), from: textView).y
            number.draw(at: NSPoint(x: placement.numberOrigin(width: size.width, in: bounds, padding: horizontalPadding),
                                   y: baseline - baselineOffset), withAttributes: attributes)
        }
    }

    override var acceptsFirstResponder: Bool { false }
    // This read-only gutter does not create text tab stops or change text selection on click.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }
}
