import AppKit
import ImageIO
import PreviewContracts

/// Draws the application icon an adapter extracted from a package. The encoded picture was bounded and
/// validated by the adapter; this view decodes it lazily, once per presentation, with an explicit pixel
/// bound so a hostile image can never allocate more than a thumbnail-sized bitmap.
@MainActor
final class PackageIconView: NSView, SafeModeContentView {
    /// Largest decoded edge. Icons are shown at most this large.
    static let maximumPixelSize = 512
    private static let displayEdge: CGFloat = 256

    var navigate: ((NativePreviewMode, NSRange) -> Void)?
    /// The icon is a picture that does not scale with the text size, so the preview's text-zoom shortcuts change
    /// nothing here and show no zoom status.
    var respondsToTextZoom: Bool { false }
    private let imageView = NSImageView()
    private var shownImage: PreviewImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.setAccessibilityRole(.image)
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualToConstant: Self.displayEdge),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: Self.displayEdge),
            imageView.widthAnchor.constraint(equalToConstant: Self.displayEdge).withPriority(.defaultLow),
            imageView.heightAnchor.constraint(equalToConstant: Self.displayEdge).withPriority(.defaultLow)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func display(_ modes: SafePreviewModes, mode: NativePreviewMode, style: SafeModeStyle) {
        layer?.backgroundColor = style.palette.background.cgColor
        guard let icon = modes.images.first(where: { $0.role == .icon }) else { clear(); return }
        if shownImage != icon {
            imageView.image = Self.decode(icon)
            shownImage = icon
        }
        imageView.setAccessibilityLabel(PreviewStrings.text(.packageIconAccessibility))
    }

    func clear() {
        imageView.image = nil
        shownImage = nil
    }

    /// The decoded icon, or `nil` when ImageIO declines it. Decoding is bounded by the thumbnail size.
    static func decode(_ image: PreviewImage) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(image.data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
