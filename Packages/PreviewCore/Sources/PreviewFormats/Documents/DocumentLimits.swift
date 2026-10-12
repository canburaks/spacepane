import Foundation
import PreviewContracts

/// Bounds shared by the ebook, comic, notebook-figure and web-archive adapters. Every limit is derived from
/// the request's budget (or is a fixed ceiling below it) and is checked before the matching allocation.
struct DocumentLimits {
    /// One encoded image. Larger members are skipped, never truncated.
    static let maximumEncodedImageBytes = 8 * 1_048_576
    /// Images carried by one presentation.
    static let maximumImageCount = 500
    /// Ceiling on the sum of all encoded images, further reduced by the request's input budget.
    static let maximumTotalImageBytes = 48 * 1_048_576
    /// Source pixels are limited before allocation, independently of the smaller requested bitmap.
    static let maximumImagePixels = PreviewImageLimits.maximumSourcePixels
    /// Length at which generated Markdown stops, in UTF-16 units. The native Rendered view declines text
    /// longer than 262,144 units and would then fall back to source, so a book stops safely below that.
    static let renderableUTF16Units = 240_000

    let context: RequestContext

    /// Aggregate encoded-image bytes: `min(48 MiB, 4 × maxInputBytes)`.
    var totalImageBytes: Int {
        min(Self.maximumTotalImageBytes, context.budget.maxInputBytes * 4)
    }

    /// Largest decompressed text member (a chapter, a package file) accepted from an archive.
    var textMemberBytes: Int {
        min(4 * 1_048_576, context.budget.maxInputBytes * 4)
    }

    /// Largest structural XML member (container, package, navigation, encryption descriptor).
    var metadataMemberBytes: Int {
        min(2 * 1_048_576, context.budget.maxInputBytes)
    }
}

/// Running totals for the encoded images a document contributes.
struct ImageCollector {
    private(set) var images: [PreviewImage] = []
    private(set) var totalBytes = 0
    private let limits: DocumentLimits

    init(limits: DocumentLimits) { self.limits = limits }

    var count: Int { images.count }
    var isFull: Bool { images.count >= DocumentLimits.maximumImageCount }

    /// Whether another image of `bytes` encoded bytes would stay within every ceiling.
    func canAccept(encodedBytes bytes: Int) -> Bool {
        !isFull && bytes <= DocumentLimits.maximumEncodedImageBytes && totalBytes + bytes <= limits.totalImageBytes
    }

    mutating func append(_ image: PreviewImage) {
        images.append(image)
        totalBytes += image.data.count
    }
}
