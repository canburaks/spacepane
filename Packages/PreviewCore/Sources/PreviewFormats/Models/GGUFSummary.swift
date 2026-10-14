import Foundation
import PreviewContracts

extension GGUFAdapter {
    /// The summary fields in display order. `layout` is `nil` for a partial read, which also leaves
    /// out every figure that needs the whole tensor table.
    static func summary(preamble: Preamble, metadata: GGUFMetadata, table: GGUFTensorTable, layout: GGUFLayoutReport?,
                        isPartial: Bool, hidden: inout ModelHiddenText, context: RequestContext) throws -> SummaryFields {
        var fields = SummaryFields()
        fields.text("name", metadata.name)
        fields.text("architecture", metadata.architecture)
        fields.text("sizeLabel", metadata.sizeLabel)
        if layout != nil { fields.number("parameters", Int64(table.parameters)) }
        fields.text("fileType", metadata.fileTypeCode.map(GGUFTypeTable.fileTypeLabel))
        if let layout {
            if let bytes = layout.totalBytes, table.parameters > 0 {
                fields.text("bitsPerWeight", String(format: "%.2f", Double(bytes) * 8 / Double(table.parameters)))
            }
            if !layout.typeCounts.isEmpty {
                let ordered = layout.typeCounts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                let shown = ordered.prefix(PackageSummary.maximumListItems)
                fields.add("tensorTypes", .object(shown.map { (GGUFTypeTable.label($0.key), SummaryValue.integer($0.value)) }))
            }
        }
        for (field, suffix) in zip(["contextLength", "blockCount", "embeddingLength", "headCount", "headCountKV",
                                    "expertCount", "expertUsedCount"], GGUFMetadataParser.architectureSuffixes) {
            let key = metadata.architecture.map { "\($0).\(suffix)" }
            fields.number(field, (key.flatMap { metadata.architectureNumbers[$0] }).map { Int64(clamping: $0) })
        }
        fields.number("vocabularySize", metadata.vocabularySize)
        fields.text("tokenizer", metadata.tokenizerModel)
        fields.text("license", metadata.license)
        fields.text("author", metadata.author)
        fields.text("organization", metadata.organization)
        fields.text("quantizedBy", metadata.quantizedBy)
        fields.list("baseModels", metadata.baseModelNames.sorted { $0.key < $1.key }.map(\.value))
        fields.list("tags", metadata.tags, limit: GGUFMetadataParser.keptListItems)
        fields.list("languages", metadata.languages, limit: GGUFMetadataParser.keptListItems)
        if let template = metadata.chatTemplate { fields.add("chatTemplate", .string(template, sensitive: false)) }
        fields.number("chatTemplateBytes", metadata.chatTemplateBytes)
        fields.number("ggufVersion", Int(preamble.version))
        fields.number("alignment", Int64(clamping: metadata.alignment))
        fields.number("tensorCount", preamble.tensorCount)
        fields.number("metadataCount", preamble.metadataCount)
        let other = metadata.other.map { ($0.key, $0.value.summary) }
        for (entry, (key, value)) in zip(metadata.other, other) {
            try hidden.scan(key, context: context)
            // A concealed value is not on screen, so it is not scanned; a named template already was, in full.
            if case .string(_, true) = value { continue }
            if !entry.isScanned { try hidden.scan(value, context: context) }
        }
        if !other.isEmpty { fields.add("otherMetadata", .object(other)) }
        var listing = ModelListingBudget(context: context)
        let shown = table.listed.prefix { listing.admit($0.name, GGUFTypeTable.label($0.typeCode)) }
        fields.flag("partial", isPartial || shown.count < preamble.tensorCount)
        if !shown.isEmpty {
            fields.add("tensors", .array(shown.map { tensor in
                .object([
                    ("name", .string(tensor.name)), ("type", .string(GGUFTypeTable.label(tensor.typeCode))),
                    ("shape", .string(tensor.shape.map(String.init).joined(separator: " × "))),
                    ("parameters", .integer(Int(clamping: tensor.elements)))
                ])
            }))
        }
        return fields
    }
}
