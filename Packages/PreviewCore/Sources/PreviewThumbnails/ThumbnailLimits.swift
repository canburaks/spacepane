import Foundation
import PreviewContracts

/// Strict, request-scoped bounds. A thumbnail is a convenience: when any bound is exceeded the
/// result is the generic glyph, never a partial or slow rendering.
public struct ThumbnailLimits: Equatable, Sendable {
    /// Pipeline budget for text-based formats: parsing and concealment together get 300 ms.
    public var textBudget: PreviewBudget
    /// SQLite files are larger than text; only the schema and a first page of rows are read.
    public var databaseBudget: PreviewBudget
    /// Absolute wall-clock bound for the whole request, including a blocked native call that the
    /// pipeline's cooperative deadline cannot interrupt.
    public var hardTimeout: Duration
    /// Encoded picture size and decoded pixel count accepted from a document.
    public var maximumImageBytes: Int
    public var maximumImagePixels: Int
    /// Documents in which the pipeline concealed more values than this draw the generic glyph. A
    /// thumbnail outlives the preview in a durable cache, so a file that visibly holds secret-like
    /// values is not summarized even in concealed form.
    public var maximumConcealedValues: Int
    /// Whether a document whose concealed text or file name still looks credential-bearing is withheld
    /// before anything is drawn (`ThumbnailSecretShape`, decision 027 D14). On by default; tests lift it
    /// the way they lift `maximumConcealedValues`, to examine what the drawing path does with such text.
    public var withholdsSecretShapes: Bool
    /// Which formats are drawn from their text although the document holds pictures (a notebook's saved figures).
    public var picturePolicy: ThumbnailPicturePolicy

    public init(textBudget: PreviewBudget = ThumbnailLimits.defaultTextBudget,
                databaseBudget: PreviewBudget = ThumbnailLimits.defaultDatabaseBudget,
                hardTimeout: Duration = .milliseconds(1_000),
                maximumImageBytes: Int = 8_388_608,
                maximumImagePixels: Int = 16_000_000,
                maximumConcealedValues: Int = 0,
                withholdsSecretShapes: Bool = true,
                picturePolicy: ThumbnailPicturePolicy = .standard) {
        self.textBudget = textBudget
        self.databaseBudget = databaseBudget
        self.hardTimeout = hardTimeout
        self.maximumImageBytes = maximumImageBytes
        self.maximumImagePixels = maximumImagePixels
        self.maximumConcealedValues = maximumConcealedValues
        self.withholdsSecretShapes = withholdsSecretShapes
        self.picturePolicy = picturePolicy
    }

    public static let defaultTextBudget = PreviewBudget(
        maxInputBytes: 262_144, maxOutputUTF8Bytes: 524_288, maxJSONDepth: 32, maxJSONNodes: 100_000,
        maxTextLines: 20_000, maxLineUTF8Bytes: 262_144, maxMilliseconds: 300)
    public static let defaultDatabaseBudget = PreviewBudget(
        maxInputBytes: 4_194_304, maxOutputUTF8Bytes: 2_097_152, maxJSONDepth: 32, maxJSONNodes: 20_000,
        maxTextLines: 20_000, maxLineUTF8Bytes: 32_768, maxMilliseconds: 500)
    public static let standard = ThumbnailLimits()

    public func budget(for format: FormatID) -> PreviewBudget {
        format == .sqlite ? databaseBudget : textBudget
    }
}
