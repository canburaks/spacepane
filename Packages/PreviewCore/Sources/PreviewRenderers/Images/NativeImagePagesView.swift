import AppKit
import PreviewContracts

/// One page of the continuous column: a placeholder sized from the image's pixel dimensions, the decoded
/// bitmap once it exists, and a caption. Drawing and accessibility live here; decoding does not.
@MainActor
final class ImagePageFrameView: NSView {
    private enum Symbol: String { case failure = "exclamationmark.circle" }

    /// The symbol and words of a frame whose picture could not be shown. Made on first use: most pages never fail.
    private struct FailureViews {
        let symbol: NSImageView
        let label: NSTextField
    }

    private(set) var image: CGImage?
    var pictureHeight: CGFloat = 0 {
        didSet {
            needsDisplay = true
            needsLayout = true
        }
    }
    var caption = "" { didSet { needsDisplay = true } }
    var placeholderColor = NSColor.clear { didSet { needsDisplay = true } }
    var captionColor = NSColor.labelColor {
        didSet {
            needsDisplay = true
            tintFailureViews()
        }
    }
    private(set) var isUnavailable = false
    private var failureViews: FailureViews?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { nil }

    var hasImage: Bool { image != nil }
    /// Actual bitmap storage includes row padding and the decoded component depth.
    var decodedBytes: Int { image.map(Self.storageBytes) ?? 0 }

    static func storageBytes(_ image: CGImage) -> Int {
        let product = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        return product.overflow ? Int.max : product.partialValue
    }

    func setImage(_ image: CGImage?) {
        self.image = image
        if image != nil { isUnavailable = false }
        showFailureViews(isUnavailable)
        needsDisplay = true
    }

    /// Replaces the placeholder with a framed one that says the picture could not be shown: a border, a symbol and
    /// `help` as words, so a failed page never looks like one that is still loading (and is never a blank gap).
    func markUnavailable(help: String) {
        image = nil
        isUnavailable = true
        setAccessibilityHelp(help)
        toolTip = help
        failureSubviews().label.stringValue = help
        showFailureViews(true)
        needsDisplay = true
    }

    func resetAvailability() {
        isUnavailable = false
        showFailureViews(false)
        setAccessibilityHelp(nil)
        toolTip = nil
    }

    // MARK: Failed picture

    private func failureSubviews() -> FailureViews {
        if let failureViews { return failureViews }
        let symbol = NSImageView()
        symbol.image = NSImage(systemSymbolName: Symbol.failure.rawValue, accessibilityDescription: nil)
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        symbol.imageScaling = .scaleProportionallyDown
        symbol.setAccessibilityElement(false)
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = NSFont.preferredFont(forTextStyle: .caption1)
        label.alignment = .center
        label.isSelectable = false
        label.setAccessibilityElement(false)
        addSubview(symbol)
        addSubview(label)
        let views = FailureViews(symbol: symbol, label: label)
        failureViews = views
        tintFailureViews()
        return views
    }

    private func tintFailureViews() {
        failureViews?.symbol.contentTintColor = captionColor
        failureViews?.label.textColor = captionColor
    }

    private func showFailureViews(_ visible: Bool) {
        guard let failureViews else { return }
        failureViews.symbol.isHidden = !visible
        failureViews.label.isHidden = !visible
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let failureViews, isUnavailable else { return }
        let arrangement = PageFailureLayout(picture: CGRect(x: 0, y: 0, width: bounds.width,
                                                           height: min(pictureHeight, bounds.height)))
        failureViews.symbol.frame = arrangement.symbol
        failureViews.symbol.isHidden = arrangement.symbol.isEmpty
        if let labelFrame = arrangement.label { failureViews.label.frame = labelFrame }
        failureViews.label.isHidden = arrangement.label == nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let picture = NSRect(x: 0, y: 0, width: bounds.width, height: min(pictureHeight, bounds.height))
        if let image {
            NSImage(cgImage: image, size: picture.size).draw(in: picture, from: .zero, operation: .sourceOver, fraction: 1,
                                                           respectFlipped: true,
                                                           hints: [.interpolation: NSImageInterpolation.high])
        } else if isUnavailable {
            // A border instead of the loading placeholder's fill: the page is empty on purpose, not still arriving.
            captionColor.setStroke()
            let outline = NSBezierPath(roundedRect: picture.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            outline.lineWidth = 1
            outline.stroke()
        } else {
            placeholderColor.setFill()
            NSBezierPath(roundedRect: picture, xRadius: 4, yRadius: 4).fill()
        }
        guard !caption.isEmpty, bounds.height > picture.height else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.preferredFont(forTextStyle: .caption1), .foregroundColor: captionColor, .paragraphStyle: paragraph
        ]
        (caption as NSString).draw(in: NSRect(x: 0, y: picture.height + 3, width: bounds.width, height: bounds.height - picture.height - 3),
                                   withAttributes: attributes)
    }
}

private final class PagesDocumentView: NSView {
    override var isFlipped: Bool { true }
    /// The page column takes keyboard focus here, in its document view, as a table or an outline takes it in theirs.
    /// The scroll view around it is not the responder, so the column is one Tab stop; keys this view does not handle
    /// travel up the responder chain to `NativeImagePagesView`.
    override var acceptsFirstResponder: Bool { true }
}

/// Continuous vertical column of embedded pictures: comic pages, an ebook cover or notebook figures.
///
/// Layout comes from `ImagePagesLayout`, so placeholder frames carry the final geometry before anything
/// decodes. Pictures decode lazily near the viewport with ImageIO at a bounded size, off the main actor, a
/// couple at a time; decoded bitmaps far from the viewport are released and a byte budget bounds the
/// resident total. `clear()` cancels every decode and drops every image, so a replacement request never
/// shows a stale page. The view reads only `SafePreviewModes.images`, never a file.
@MainActor
final class NativeImagePagesView: NSScrollView, SafeModeContentView, PreviewAnnouncing {
    /// Upper bound on decoded bitmap memory kept resident across all pages.
    static let maximumResidentBytes = 192 * 1_048_576

    var navigate: ((NativePreviewMode, NSRange) -> Void)?
    /// Speaks "Find is not available here" when Find is pressed while the pages have focus. Pages made on their own
    /// keep this one; the hosting preview replaces it with its own.
    var announcer: PreviewAnnouncer? = PreviewAnnouncer()
    /// Bytes of decoded bitmaps this view may keep; tests lower it to exercise eviction.
    var residentByteLimit = NativeImagePagesView.maximumResidentBytes
    /// Called with the position of the page at the top ("Page 3 of 1,200") each time it changes, and with nil when
    /// the pictures go away or there is only one. The hosting preview shows it in its limits strip; a view used on
    /// its own ignores it.
    var onPositionChange: (@MainActor (PresentationNotice?) -> Void)?

    private struct Fingerprint: Equatable {
        let byteCount: Int, width: Int, height: Int, role: PreviewImage.Role, sample: Int
        init(_ image: PreviewImage) {
            byteCount = image.data.count
            width = image.pixelWidth
            height = image.pixelHeight
            role = image.role
            var hasher = Hasher()
            hasher.combine(image.data.prefix(256))
            hasher.combine(image.data.suffix(256))
            sample = hasher.finalize()
        }
    }

    private let documentContainer = PagesDocumentView()
    private let scheduler: ImagePageScheduler
    private var images: [PreviewImage] = []
    private var fingerprint: [Fingerprint] = []
    private var totalPages = 0
    private var pageViews: [ImagePageFrameView] = []
    private var failed: Set<Int> = []
    private var pagesLayout = ImagePagesLayout.empty
    private var laidOutWidth: CGFloat = 0
    private var laidOutScale: CGFloat = 0
    private var style: SafeModeStyle?
    private var locale = Locale.current
    /// The page index last reported through `onPositionChange`; nil when nothing was reported or it was nil.
    private var reportedPageIndex: Int?

    init(frame frameRect: NSRect, scheduler: ImagePageScheduler) {
        self.scheduler = scheduler
        super.init(frame: frameRect)
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        borderType = .noBorder
        documentView = documentContainer
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsChanged),
                                               name: NSView.boundsDidChangeNotification, object: contentView)
        scheduler.deliver = { [weak self] index, result in self?.receive(index, result) }
        setAccessibilityLabel(PreviewStrings.text(.previewModePages))
        setAccessibilityHelp(PreviewStrings.text(.ebooksPagesHelp))
    }

    convenience override init(frame frameRect: NSRect) {
        self.init(frame: frameRect, scheduler: ImagePageScheduler())
    }

    required init?(coder: NSCoder) { nil }

    // MARK: SafeModeContentView

    /// Pages are pictures laid out by width, so the text-size shortcuts have nothing to restyle here.
    var respondsToTextZoom: Bool { false }

    func display(_ modes: SafePreviewModes, mode: NativePreviewMode, style: SafeModeStyle) {
        guard mode == .pages else { return }
        self.style = style
        locale = style.locale
        let newFingerprint = modes.pageImages.map(Fingerprint.init)
        let newTotal = max(modes.pageImages.count, modes.imagePageTotal ?? 0)
        if newFingerprint != fingerprint || newTotal != totalPages {
            rebuild(modes.pageImages, total: newTotal, fingerprint: newFingerprint)
        }
        applyStyle()
        relayoutIfNeeded(force: false)
        // A new locale words the same position differently, so the next report always goes out.
        reportedPageIndex = nil
        refreshVisiblePages()
    }

    func clear() {
        scheduler.cancelAll()
        for view in pageViews { view.removeFromSuperview() }
        pageViews = []
        images = []
        fingerprint = []
        totalPages = 0
        failed = []
        pagesLayout = .empty
        laidOutWidth = 0
        documentContainer.setFrameSize(.zero)
        reportPosition()
    }

    // MARK: Inspection (tests)

    var pageCount: Int { pageViews.count }
    var pageFrames: [CGRect] { pagesLayout.frames }
    var decodedPageIndices: [Int] { pageViews.indices.filter { pageViews[$0].hasImage } }
    var residentBytes: Int {
        pageViews.reduce(0) {
            let sum = $0.addingReportingOverflow($1.decodedBytes)
            return sum.overflow ? Int.max : sum.partialValue
        }
    }
    func pageView(at index: Int) -> ImagePageFrameView? { pageViews.indices.contains(index) ? pageViews[index] : nil }

    // MARK: Building

    private func rebuild(_ newImages: [PreviewImage], total: Int, fingerprint newFingerprint: [Fingerprint]) {
        clear()
        images = newImages
        fingerprint = newFingerprint
        totalPages = total
        for _ in newImages.indices {
            let page = ImagePageFrameView(frame: .zero)
            documentContainer.addSubview(page)
            pageViews.append(page)
        }
        laidOutWidth = 0
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
    }

    private func applyStyle() {
        guard let style else { return }
        documentContainer.wantsLayer = true
        documentContainer.layer?.backgroundColor = style.palette.background.cgColor
        backgroundColor = style.palette.background
        drawsBackground = true
        let numbering = Self.numbering(for: images)
        for (index, page) in pageViews.enumerated() {
            let label = Self.label(for: images[index], number: numbering[index], total: totalFor(images[index].role),
                                   locale: style.locale)
            page.caption = label
            page.setAccessibilityLabel(label)
            page.placeholderColor = style.palette.hairline
            page.captionColor = style.palette.muted
            // No tooltip names a page: an adapter-chosen label (an archive member path) is untrusted text that
            // never passes the privacy filter or the hidden-character scan, and the localized label above serves.
            if page.isUnavailable { page.markUnavailable(help: PreviewStrings.text(.ebooksPagesUnavailable)) }
        }
        setAccessibilityLabel(PreviewStrings.text(.previewModePages))
        setAccessibilityHelp(PreviewStrings.text(.ebooksPagesHelp))
    }

    private func totalFor(_ role: PreviewImage.Role) -> Int {
        role == .page ? max(totalPages, images.filter { $0.role == .page }.count) : images.filter { $0.role == role }.count
    }

    /// Position of each image among images of its own role, so figures and pages count independently.
    static func numbering(for images: [PreviewImage]) -> [Int] {
        var counts: [PreviewImage.Role: Int] = [:]
        return images.map { image in
            counts[image.role, default: 0] += 1
            return counts[image.role] ?? 1
        }
    }

    static func label(for image: PreviewImage, number: Int, total: Int, locale: Locale) -> String {
        let arguments: [CVarArg] = [number.formatted(.number.locale(locale)), total.formatted(.number.locale(locale))]
        switch image.role {
        case .cover: return PreviewStrings.text(.ebooksPagesCover)
        case .page: return PreviewStrings.format(.ebooksPagesPage, arguments: arguments, locale: locale)
        case .figure: return PreviewStrings.format(.ebooksPagesFigure, arguments: arguments, locale: locale)
        case .icon: return PreviewStrings.format(.ebooksPagesImage, arguments: arguments, locale: locale)
        }
    }

    // MARK: Layout

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    override func layout() {
        super.layout()
        relayoutIfNeeded(force: false)
        refreshVisiblePages()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            // A closed preview keeps no decoded bitmaps and no running decodes.
            scheduler.cancelAll()
            for page in pageViews { page.setImage(nil) }
        } else {
            relayoutIfNeeded(force: true)
            refreshVisiblePages()
        }
    }

    private func relayoutIfNeeded(force: Bool) {
        let width = contentView.bounds.width
        let scale = backingScale
        guard !images.isEmpty, width > 0 else { return }
        guard force || width != laidOutWidth || scale != laidOutScale else { return }
        laidOutWidth = width
        laidOutScale = scale
        pagesLayout = ImagePagesLayout(pixelSizes: images.map { CGSize(width: $0.pixelWidth, height: $0.pixelHeight) },
                                  viewportWidth: width, backingScale: scale)
        documentContainer.setFrameSize(NSSize(width: width, height: max(pagesLayout.contentSize.height, contentView.bounds.height)))
        for (index, page) in pageViews.enumerated() where pagesLayout.frames.indices.contains(index) {
            page.frame = pagesLayout.frames[index]
            page.pictureHeight = pagesLayout.pictureHeights[index]
        }
    }

    // MARK: Lazy decoding

    @objc nonisolated private func clipBoundsChanged() {
        Task { @MainActor [weak self] in self?.refreshVisiblePages() }
    }

    /// Requests decodes for pages within one viewport of the visible area, releases bitmaps farther than two
    /// viewports away, and keeps resident bitmap memory under `maximumResidentBytes`.
    func refreshVisiblePages() {
        reportPosition()
        guard !images.isEmpty, pagesLayout.frames.count == images.count else { return }
        let visible = contentView.documentVisibleRect
        let height = max(visible.height, 1)
        let keep = pagesLayout.indices(intersecting: visible.minY - 2 * height, visible.maxY + 2 * height)
        let prefetch = pagesLayout.indices(intersecting: visible.minY - height, visible.maxY + height)
        for index in pageViews.indices where pageViews[index].hasImage && !keep.contains(index) { pageViews[index].setImage(nil) }

        var resident = residentBytes
        let byteLimit = max(0, residentByteLimit)
        let center = visible.midY
        let candidates = prefetch.filter { !pageViews[$0].hasImage && !failed.contains($0) }
            .sorted { abs(pagesLayout.frames[$0].midY - center) < abs(pagesLayout.frames[$1].midY - center) }
        var requests: [ImagePageScheduler.Request] = []
        for index in candidates {
            let estimate = estimatedBytes(for: index)
            // Make room by dropping the resident bitmap farthest from the viewport that is not visible.
            while estimate > max(0, byteLimit - resident),
                  let victim = farthestEvictable(from: center, visible: visible) {
                resident -= pageViews[victim].decodedBytes
                pageViews[victim].setImage(nil)
            }
            guard estimate <= max(0, byteLimit - resident) else { break }
            resident += estimate
            requests.append(.init(index: index, maximumPixelSize: decodeSize(for: index), image: images[index]))
        }
        scheduler.want(requests)
    }

    private func farthestEvictable(from center: CGFloat, visible: CGRect) -> Int? {
        decodedPageIndices.filter { !pagesLayout.frames[$0].intersects(visible) }
            .max { abs(pagesLayout.frames[$0].midY - center) < abs(pagesLayout.frames[$1].midY - center) }
    }

    private func decodeSize(for index: Int) -> Int {
        ImagePagesLayout.decodePixelSize(pixelWidth: images[index].pixelWidth, pixelHeight: images[index].pixelHeight,
                                         displayWidth: pagesLayout.frames[index].width, backingScale: backingScale)
    }

    private func estimatedBytes(for index: Int) -> Int {
        let side = CGFloat(decodeSize(for: index))
        let width = CGFloat(images[index].pixelWidth)
        let height = CGFloat(images[index].pixelHeight)
        let factor = side / max(width, height)
        return Int((width * factor).rounded(.up) * (height * factor).rounded(.up) * 4)
    }

    private func receive(_ index: Int, _ result: DecodedPageImage?) {
        guard pageViews.indices.contains(index) else { return }
        guard let result else {
            failed.insert(index)
            pageViews[index].markUnavailable(help: PreviewStrings.text(.ebooksPagesUnavailable))
            return
        }
        let bytes = ImagePageFrameView.storageBytes(result.image)
        let byteLimit = max(0, residentByteLimit)
        var resident = residentBytes - pageViews[index].decodedBytes
        let visible = contentView.documentVisibleRect
        while bytes > max(0, byteLimit - resident),
              let victim = farthestEvictable(from: visible.midY, visible: visible) {
            resident -= pageViews[victim].decodedBytes
            pageViews[victim].setImage(nil)
        }
        guard bytes <= max(0, byteLimit - resident) else {
            failed.insert(index)
            pageViews[index].markUnavailable(help: PreviewStrings.text(.ebooksPagesUnavailable))
            return
        }
        pageViews[index].setImage(result.image)
        refreshVisiblePages()
    }

    // MARK: Keyboard

    /// The view inside the page column that takes keyboard focus: its document container
    /// (`SafeModeContentView.keyboardFocusTarget`).
    var keyboardFocusTarget: NSView? { documentContainer }

    /// Whether the page column, or a view inside it, is the window's first responder. Arrows and paging act only
    /// then, so they stay Quick Look's while focus is anywhere else.
    var hasKeyboardFocus: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: self)
    }

    /// Gives the page column keyboard focus. Returns whether the window accepted it; false without a window.
    @discardableResult
    func takeKeyboardFocus() -> Bool {
        window?.makeFirstResponder(documentContainer) ?? false
    }

    override func mouseDown(with event: NSEvent) {
        takeKeyboardFocus()
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Space and Escape belong to Quick Look: hand them on untouched, ahead of the scroll view's own key handling.
        if PreviewKeyPolicy.reservesForHost(keyCode: event.keyCode), let next = nextResponder {
            next.keyDown(with: event)
            return
        }
        if !handleNavigationKey(event) { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Keys reach a key equivalent first (Command-Up and Command-Down among them); claim them only while the page
        // column has focus.
        guard hasKeyboardFocus else { return super.performKeyEquivalent(with: event) }
        // There is nothing to search among pictures: say so instead of staying silent.
        if PreviewKeyPolicy.answerFindUnavailable(event, using: announcer, from: self) { return true }
        return handleNavigationKey(event) || super.performKeyEquivalent(with: event)
    }

    /// Arrows, Page Up/Down, Home/End and Command-Up/Down. It runs only while the page column has keyboard
    /// focus (a key-down goes to the first responder, and the key-equivalent path checks), so the arrows never act
    /// for the preview as a whole. Space is deliberately absent: Quick Look owns it. Returns whether the key was
    /// handled.
    @discardableResult
    func handleNavigationKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = modifiers.contains(.command)
        let page = max(40, contentView.bounds.height * 0.9)
        switch event.keyCode {
        case 125: command ? scrollToEnd() : scrollBy(40)
        case 126: command ? scrollToStart() : scrollBy(-40)
        case 121: scrollBy(page)
        case 116: scrollBy(-page)
        case 115: scrollToStart()
        case 119: scrollToEnd()
        case 124: scrollToPage(offset: userInterfaceLayoutDirection == .rightToLeft ? -1 : 1)
        case 123: scrollToPage(offset: userInterfaceLayoutDirection == .rightToLeft ? 1 : -1)
        default: return false
        }
        return true
    }

    func scrollToStart() { scroll(toY: 0) }
    func scrollToEnd() { scroll(toY: .greatestFiniteMagnitude) }
    private func scrollBy(_ delta: CGFloat) { scroll(toY: contentView.documentVisibleRect.minY + delta) }

    /// Moves to the top of the next or previous page, relative to the page at the top of the viewport.
    func scrollToPage(offset: Int) {
        guard !pagesLayout.frames.isEmpty else { return }
        // Pages scroll to just below the top inset, so "the page at the top" is measured from the inset's lower edge.
        let top = contentView.documentVisibleRect.minY + ImagePagesLayout.verticalInset
        var current = pagesLayout.lastIndex(startingAtOrBefore: top) ?? 0
        if offset < 0, top > pagesLayout.frames[current].minY + 4 { current += 1 }   // Back to the top of the current page first.
        let target = min(max(current + offset, 0), pagesLayout.frames.count - 1)
        scroll(toY: pagesLayout.frames[target].minY - ImagePagesLayout.verticalInset)
    }

    private func scroll(toY y: CGFloat) {
        let maximum = max(0, documentContainer.frame.height - contentView.bounds.height)
        contentView.scroll(to: NSPoint(x: contentView.bounds.origin.x, y: min(max(0, y), maximum)))
        reflectScrolledClipView(contentView)
        refreshVisiblePages()
    }

    /// Index of the page at the top of the viewport.
    var topPageIndex: Int? {
        pagesLayout.lastIndex(startingAtOrBefore: contentView.documentVisibleRect.minY + ImagePagesLayout.verticalInset)
    }

    // MARK: Position

    /// The page at the top of the viewport, worded like its accessibility label ("Page 3 of 1,200", "Figure 2 of 5"),
    /// as a limits notice. Nil unless the document has more than one picture (a lone cover has no position to
    /// report); a comic that carries one page of 1,200 still has a position.
    var positionNotice: PresentationNotice? {
        guard let index = positionIndex else { return nil }
        let image = images[index]
        let text = Self.label(for: image, number: Self.numbering(for: images)[index], total: totalFor(image.role), locale: locale)
        return PresentationNotice(kind: .limit, text: text)
    }

    private var positionIndex: Int? {
        guard totalPages > 1, pagesLayout.frames.count == images.count, let index = topPageIndex,
              images.indices.contains(index) else { return nil }
        return index
    }

    /// Tells the host when the top page changes. Only the index is compared while scrolling, so the text is built
    /// once per page, not once per scroll event.
    private func reportPosition() {
        let index = positionIndex
        guard index != reportedPageIndex else { return }
        reportedPageIndex = index
        onPositionChange?(positionNotice)
    }
}
