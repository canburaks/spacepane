import Foundation
import PreviewContracts

extension SafetensorsAdapter {
    static let listedNameBytes = 256

    static func summary(header: SafetensorsHeader, analysis: SafetensorsAnalysis, headerLength: UInt64, fileName: String?,
                        hidden: inout ModelHiddenText, context: RequestContext) throws -> SummaryFields {
        var fields = SummaryFields()
        fields.number("tensorCount", header.tensors.count)
        fields.number("parameters", Int64(clamping: analysis.parameters))
        if !analysis.dtypeCounts.isEmpty {
            let ordered = analysis.dtypeCounts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            let shown = ordered.prefix(PackageSummary.maximumListItems)
                .map { (PackageSummary.clipped($0.key, limit: 64), SummaryValue.integer($0.value)) }
            for (name, _) in shown { try hidden.scan(name, context: context) }
            fields.add("dtypes", .object(shown))
        }
        let format = header.metadata.first { $0.key == "format" }?.value
        fields.text("format", format)
        fields.text("shard", SafetensorsConventions.shard(fromFileName: fileName))
        if let kind = SafetensorsConventions.adapterKind(header.tensors) {
            fields.text("adapterKind", kind)
            fields.number("loraRank", SafetensorsConventions.loraRank(header.tensors))
        }
        fields.text("quantization", SafetensorsConventions.quantization(header.tensors))
        fields.number("headerBytes", Int64(clamping: headerLength))
        fields.number("dataBytes", Int64(clamping: analysis.dataBytes))

        var metadata: [(String, SummaryValue)] = []
        for (key, value) in header.metadata {
            let sensitive = SecretFieldPolicy.isSensitive(key)
            let shownKey = PackageSummary.clipped(key, limit: 256)
            let shownValue = PackageSummary.clipped(value)
            try hidden.scan(shownKey, context: context)
            // A concealed value is not on screen, so it is not scanned.
            if !sensitive { try hidden.scan(shownValue, context: context) }
            metadata.append((shownKey, .string(shownValue, sensitive: sensitive)))
        }
        if !metadata.isEmpty { fields.add("metadata", .object(metadata)) }

        let capacity = PackageSummary.listingCapacity(context)
        var listing = ModelListingBudget(context: context)
        let listed = header.tensors.prefix(capacity).prefix { listing.admit($0.name, $0.dtype) }
        fields.flag("partial", header.tensors.count > listed.count)
        var entries: [SummaryValue] = []
        for (index, tensor) in listed.enumerated() {
            let name = PackageSummary.clipped(tensor.name, limit: listedNameBytes)
            try hidden.scan(name, context: context)
            entries.append(.object([
                ("name", .string(name)), ("dtype", .string(PackageSummary.clipped(tensor.dtype, limit: 64))),
                ("shape", .string(tensor.shape.map(String.init).joined(separator: " × "))),
                ("parameters", .integer(Int(clamping: analysis.elementCounts[index])))
            ]))
        }
        if !entries.isEmpty { fields.add("tensors", .array(entries)) }
        return fields
    }
}
