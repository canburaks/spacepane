import Foundation
import PreviewContracts

/// Counts invisible and deceptive characters in the strings a model summary shows (names, metadata
/// values, the chat template), the way the hidden-content scan counts them for source text: one
/// finding per class, `count` the number of scalars, no lines and no decoded text. Summaries are
/// app-made text, so the pipeline's own scan skips them; GGUF and safetensors adapters call this
/// instead. Shared by both adapters.
struct ModelHiddenText {
    private var scalarCounts: [HiddenCharacterClass: Int] = [:]

    /// Scans one file-supplied string. Text that is all ASCII costs one byte test.
    mutating func scan(_ text: String, context: RequestContext) throws {
        guard !text.utf8.allSatisfy({ $0 < 0x80 }) else { return }
        for span in try HiddenCharacters.spans(in: text, checkpoint: context.checkpoint) {
            scalarCounts[span.kind, default: 0] += span.scalarCount
        }
    }

    /// Scans every string a summary value holds: its text values, not its object keys.
    mutating func scan(_ value: SummaryValue, context: RequestContext) throws {
        switch value {
        case .string(let text, _): try scan(text, context: context)
        case .array(let items): for item in items { try scan(item, context: context) }
        case .object(let pairs):
            for (key, item) in pairs {
                try scan(key, context: context)
                try scan(item, context: context)
            }
        case .integer, .boolean, .null: break
        }
    }

    mutating func merge(_ other: ModelHiddenText) {
        for (characterClass, count) in other.scalarCounts { scalarCounts[characterClass, default: 0] += count }
    }

    var findings: [PreviewFinding] {
        HiddenCharacterClass.allCases.compactMap { characterClass in
            guard let count = scalarCounts[characterClass], count > 0 else { return nil }
            return PreviewFinding(kind: Self.kind(characterClass), count: count)
        }
    }

    private static func kind(_ characterClass: HiddenCharacterClass) -> PreviewFindingKind {
        switch characterClass {
        case .bidirectionalControl: .hiddenBidirectionalControls
        case .zeroWidth: .hiddenZeroWidth
        case .tag: .hiddenUnicodeTags
        case .variationSelector: .hiddenVariationSelectors
        case .privateUse: .hiddenPrivateUse
        }
    }
}
