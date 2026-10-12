import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

// Decision 027, Q-76 (review DM-22): a page whose picture could not be decoded was drawn exactly like one that was
// still loading. A failed frame is now a framed placeholder with a symbol and the localized words, never a blank gap.

private let loadingFill = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
private let ink = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)

@Suite("Failed page frames", .serialized)
@MainActor
struct DocumentsQ76PageFrameTests {
    private let help = PreviewStrings.text(.ebooksPagesUnavailable)

    private func makeFrame(width: CGFloat = 200, height: CGFloat = 280,
                           captionBand: CGFloat = ImagePagesLayout.captionHeight) -> ImagePageFrameView {
        let page = ImagePageFrameView(frame: NSRect(x: 0, y: 0, width: width, height: height + captionBand))
        page.pictureHeight = height
        page.placeholderColor = loadingFill
        page.captionColor = ink
        page.caption = "Page 1 of 2"
        return page
    }

    private func symbol(in page: ImagePageFrameView) -> NSImageView? { descendants(of: NSImageView.self, in: page).first }
    private func words(in page: ImagePageFrameView) -> NSTextField? { descendants(of: NSTextField.self, in: page).first }
    private func isShown(_ view: NSView?) -> Bool { view.map { !$0.isHidden } ?? false }

    private func bitmap(of view: NSView) throws -> NSBitmapImageRep {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(view.bounds.width)), pixelsHigh: Int(ceil(view.bounds.height)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    /// The color of the pixel in the left edge column, halfway down the picture.
    private func edgeColor(of page: ImagePageFrameView) throws -> NSColor {
        let image = try bitmap(of: page)
        let color = try #require(image.colorAt(x: 0, y: Int(page.pictureHeight / 2)))
        return try #require(color.usingColorSpace(.sRGB))
    }

    private func isRed(_ color: NSColor) -> Bool { color.redComponent > 0.8 && color.greenComponent < 0.3 && color.blueComponent < 0.3 }
    private func isBlue(_ color: NSColor) -> Bool { color.blueComponent > 0.8 && color.redComponent < 0.3 && color.greenComponent < 0.3 }

    private func modes(for images: [PreviewImage]) -> SafePreviewModes {
        SafePreviewModes(presentation(.comicBook, text: "{}", syntax: .json, images: images), locale: Locale(identifier: "en"))
    }

    // MARK: The placeholder

    @Test func aFailedFrameShowsASymbolAndTheLocalizedWordsInsideItsPicture() throws {
        let page = makeFrame()
        page.markUnavailable(help: help)
        page.layoutSubtreeIfNeeded()
        let symbolView = try #require(symbol(in: page))
        let wordsView = try #require(words(in: page))
        #expect(symbolView.image != nil && !symbolView.isHidden)
        #expect(wordsView.stringValue == help && !wordsView.isHidden)
        let picture = CGRect(x: 0, y: 0, width: 200, height: 280)
        #expect(picture.contains(symbolView.frame) && picture.contains(wordsView.frame))
        // The symbol sits above the words, centered, and the pair does not overlap.
        #expect(symbolView.frame.maxY <= wordsView.frame.minY)
        #expect(abs(symbolView.frame.midX - picture.midX) <= 1)
        // Neither piece is a separate accessibility element: the frame keeps speaking as one labeled image.
        #expect(!symbolView.isAccessibilityElement() && !wordsView.isAccessibilityElement())
    }

    @Test func theSymbolAndWordsUseThePaletteInk() throws {
        let page = makeFrame()
        page.markUnavailable(help: help)
        let symbolView = try #require(symbol(in: page))
        let wordsView = try #require(words(in: page))
        #expect(symbolView.contentTintColor == ink)
        #expect(wordsView.textColor == ink)
        // A later palette (an appearance change) restyles them without making new views.
        let quiet = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        page.captionColor = quiet
        #expect(symbolView.contentTintColor == quiet && wordsView.textColor == quiet)
        #expect(descendants(of: NSImageView.self, in: page).count == 1)
    }

    @Test func aFrameThatIsStillLoadingHasNoFailureViews() {
        let page = makeFrame()
        page.layoutSubtreeIfNeeded()
        #expect(descendants(of: NSImageView.self, in: page).isEmpty)
        #expect(descendants(of: NSTextField.self, in: page).isEmpty)
    }

    @Test func aPictureThatArrivesLaterRemovesThePlaceholder() {
        let page = makeFrame()
        page.markUnavailable(help: help)
        page.setImage(testBitmap(width: 20, height: 28))
        page.layoutSubtreeIfNeeded()
        #expect(!page.isUnavailable)
        #expect(!isShown(symbol(in: page)) && !isShown(words(in: page)))
    }

    @Test func resettingAvailabilityHidesThePlaceholderToo() {
        let page = makeFrame()
        page.markUnavailable(help: help)
        page.resetAvailability()
        page.layoutSubtreeIfNeeded()
        #expect(!page.isUnavailable)
        #expect(!isShown(symbol(in: page)) && !isShown(words(in: page)))
        #expect(page.toolTip == nil && page.accessibilityHelp() == nil)
    }

    // MARK: Failed is not loading

    @Test func aFailedFrameIsDrawnWithABorderWhereALoadingOneIsFilled() throws {
        let failed = makeFrame()
        failed.markUnavailable(help: help)
        failed.layoutSubtreeIfNeeded()
        let loading = makeFrame()
        loading.layoutSubtreeIfNeeded()
        let failedEdge = try edgeColor(of: failed)
        let loadingEdge = try edgeColor(of: loading)
        #expect(isRed(failedEdge))
        #expect(isBlue(loadingEdge))
        let failedPixels = try bitmap(of: failed).tiffRepresentation
        let loadingPixels = try bitmap(of: loading).tiffRepresentation
        #expect(failedPixels != loadingPixels)
    }

    @Test func aSmallFailedFrameKeepsItsBorderEvenWhenNothingElseFits() throws {
        let small = makeFrame(width: 20, height: 20, captionBand: 0)
        small.markUnavailable(help: help)
        small.layoutSubtreeIfNeeded()
        #expect(!isShown(symbol(in: small)) && !isShown(words(in: small)))
        let smallEdge = try edgeColor(of: small)
        #expect(isRed(smallEdge))
        let medium = makeFrame(width: 44, height: 44, captionBand: 0)
        medium.markUnavailable(help: help)
        medium.layoutSubtreeIfNeeded()
        // Room for the symbol, not for words.
        #expect(isShown(symbol(in: medium)) && !isShown(words(in: medium)))
    }

    // MARK: In the column

    @Test func aPageWhoseDecodeFailsGetsThePlaceholderAndKeepsItsLabelsAndHelp() async throws {
        let view = NativeImagePagesView(frame: NSRect(x: 0, y: 0, width: 600, height: 400),
                                        scheduler: ImagePageScheduler(maximumConcurrent: 2, decode: { _, _ in nil }))
        view.layoutSubtreeIfNeeded()
        let style = testStyle()
        view.display(modes(for: testPages(2)), mode: .pages, style: style)
        #expect(await waitUntil { view.pageView(at: 0)?.isUnavailable == true })
        let page = try #require(view.pageView(at: 0))
        page.layoutSubtreeIfNeeded()
        let wordsView = try #require(words(in: page))
        #expect(wordsView.stringValue == help && !wordsView.isHidden)
        #expect(isShown(symbol(in: page)))
        // The words and symbol are drawn in the palette's muted ink, like the caption.
        #expect(wordsView.textColor == style.palette.muted)
        // Speech and the tooltip are as they were: the position label, and the same sentence as help.
        #expect(page.accessibilityLabel() == "Page 1 of 2")
        #expect(page.caption == "Page 1 of 2")
        #expect(page.accessibilityHelp() == help)
        #expect(page.toolTip == help)
        // Restyling (a new locale or appearance) keeps the placeholder.
        view.display(modes(for: testPages(2)), mode: .pages, style: testStyle(locale: Locale(identifier: "de")))
        #expect(page.isUnavailable)
        #expect(descendants(of: NSImageView.self, in: page).count == 1)
        view.clear()
    }

    @Test func aReplacementDocumentDoesNotInheritAFailedFrame() async throws {
        // The second page of the first document cannot be decoded; every page of the replacement can.
        let failing = Data("page-1".utf8)
        let scheduler = ImagePageScheduler(maximumConcurrent: 2, decode: { image, size in
            image.data == failing ? nil : DecodedPageImage(image: testBitmap(width: max(1, size * 100 / 140), height: size))
        })
        let view = NativeImagePagesView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), scheduler: scheduler)
        view.layoutSubtreeIfNeeded()
        view.display(modes(for: testPages(2)), mode: .pages, style: testStyle())
        #expect(await waitUntil { view.pageView(at: 1)?.isUnavailable == true })
        let replacement = (0..<3).map { PreviewImage(data: Data("other-\($0)".utf8), pixelWidth: 60, pixelHeight: 90, role: .page) }
        view.display(modes(for: replacement), mode: .pages, style: testStyle())
        #expect(view.pageCount == 3)
        #expect(await waitUntil { view.decodedPageIndices.count == 3 })
        for index in 0..<3 {
            let page = try #require(view.pageView(at: index))
            #expect(!page.isUnavailable)
            #expect(descendants(of: NSImageView.self, in: page).isEmpty)
        }
        view.clear()
    }
}
