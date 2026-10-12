import PreviewContracts

/// Which formats are drawn from their text even when the document holds pictures (decision 027, Q-127; thumbnails
/// review TH-05).
///
/// A cover, an icon or a page identifies the document it belongs to. A notebook's pictures are something else:
/// figures that code cells saved as output, which are results of a run and can hold real data. Decision 022 draws
/// a notebook's first cells, and the durable thumbnail cache is no place for its plots, so the standard policy
/// keeps the notebook on its cells. The owner has not decided whether a notebook may stand for itself with its
/// first figure; when that is decided the choice is this set (an empty set draws the first figure when there is
/// one), keyed by the catalog's format identity and not by a suffix.
///
/// The catalog has no field for this today. If the owner wants the choice per format, it belongs in the catalog
/// entry next to the thumbnail policy and this type then reads it.
public struct ThumbnailPicturePolicy: Equatable, Sendable {
    /// Formats whose pictures are never tried; their text is the thumbnail.
    public var textOnlyFormats: Set<FormatID>

    public init(textOnlyFormats: Set<FormatID>) {
        self.textOnlyFormats = textOnlyFormats
    }

    /// Notebooks are drawn from their cells.
    public static let standard = ThumbnailPicturePolicy(textOnlyFormats: [.jupyterNotebook])

    /// False when the format's pictures must not be drawn.
    public func allowsPictures(for format: FormatID) -> Bool {
        !textOnlyFormats.contains(format)
    }
}
