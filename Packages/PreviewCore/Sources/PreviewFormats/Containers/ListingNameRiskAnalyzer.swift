import Foundation
import PreviewContracts

/// Name checks shared by archive and folder listings. Findings count entries without carrying
/// names or decoded hidden payloads; the displayed path always keeps its original code units.
enum ListingNameRiskAnalyzer {
    static func risks(in path: String, context: RequestContext) throws -> Set<ArchiveEntryRisk> {
        try context.checkpoint()
        var risks: Set<ArchiveEntryRisk> = []
        // Filename direction marks remain a risk even when legitimate RTL letters exempt them in text.
        for (index, scalar) in path.unicodeScalars.enumerated() {
            if index.isMultiple(of: 4096) { try context.checkpoint() }
            if HiddenCharacters.isBidirectionalControl(scalar) { risks.insert(.directionalName); break }
        }
        for span in try HiddenCharacters.spans(in: path, checkpoint: context.checkpoint) {
            switch span.kind {
            case .zeroWidth, .tag, .variationSelector: risks.insert(.hiddenCharacters)
            case .bidirectionalControl, .privateUse: break
            }
        }
        return risks
    }

    static func analyze(_ entries: [ContainerEntry], context: RequestContext) throws -> ArchiveRiskReport {
        try context.checkpoint()
        guard entries.count <= ContainerLimits(context: context).maxEntries else { throw PreviewFailure.tooManyNodes }
        var entryRisks: [[ArchiveEntryRisk]] = []
        entryRisks.reserveCapacity(entries.count)
        var counts: [ArchiveEntryRisk: Int] = [:]
        for entry in entries {
            let found = try risks(in: entry.path, context: context)
            let ordered = ArchiveEntryRisk.allCases.filter(found.contains)
            entryRisks.append(ordered)
            for risk in ordered { counts[risk, default: 0] += 1 }
        }
        let findings = ArchiveEntryRisk.allCases.compactMap { risk -> PreviewFinding? in
            guard let count = counts[risk] else { return nil }
            return PreviewFinding(kind: risk.findingKind, count: count)
        }
        return ArchiveRiskReport(entryRisks: entryRisks, findings: findings)
    }
}
