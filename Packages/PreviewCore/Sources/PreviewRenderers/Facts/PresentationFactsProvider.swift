import Foundation
import PreviewContracts

/// Value-free facts from already supplied metadata and cached safe models. No source is read or parsed here.
enum PresentationFactsProvider {
    static func facts(for presentation: TextPresentation, modes: SafePreviewModes) -> PresentationFacts {
        let isText = presentation.origin == .source || presentation.origin == .reformatted
        let isSourcePrefix = isText && presentation.truncatedSourceBytes != nil
        let isDelimitedSource = isText && (presentation.formatID == .csv || presentation.formatID == .tsv)
            && (presentation.syntax == .commaSeparated || presentation.syntax == .tabSeparated)
        var facts = presentation.facts.facts.map { fact in
            if isDelimitedSource, isSourcePrefix,
               case .grid(let rows, let columns, _) = fact {
                return PresentationFacts.Fact.grid(rows: rows, columns: columns, rowsAreLowerBound: true)
            }
            return fact
        }
        func appendIfAbsent(_ fact: PresentationFacts.Fact) {
            guard !facts.contains(where: { family(of: $0) == family(of: fact) }) else { return }
            facts.append(fact)
        }
        for fact in modes.listingFacts.facts { appendIfAbsent(fact) }
        for fact in modes.notebookFacts.facts { appendIfAbsent(fact) }
        if isDelimitedSource, let table = modes.table, table.origin == .delimitedText,
           !table.truncation.contains(.columns), !table.truncation.contains(.cells) {
            appendIfAbsent(.grid(rows: table.rows.count, columns: table.columns.count,
                rowsAreLowerBound: table.isPartialRead || table.truncation.contains(.rows)))
        }
        if let midi = presentation.midi {
            appendIfAbsent(.playback(tracks: midi.trackCount, seconds: midi.durationSeconds))
        }
        if let count = modes.imagePageTotal { appendIfAbsent(.records(count, .pages)) }
        if presentation.syntax == .drawio, let count = presentation.sourceRecordCount {
            appendIfAbsent(.records(count, .pages))
        }
        if let cues = modes.cues { appendIfAbsent(.records(cues.count, .cues, isLowerBound: isSourcePrefix)) }
        if presentation.formatID == .jsonLines,
           !facts.contains(where: { if case .grid = $0 { return true }; return false }),
           let count = presentation.sourceRecordCount ?? modes.records?.count {
            appendIfAbsent(.records(count, .records, isLowerBound: isSourcePrefix))
        }
        let images = modes.images.filter(\.isValid)
        // Adapters may carry only a cover or a bounded subset; this is an at-least count unless typed facts say more.
        if !images.isEmpty { appendIfAbsent(.records(images.count, .images, isLowerBound: true)) }
        let pictures = images.filter { $0.role != .icon }
        let relevantImages = pictures.isEmpty ? images : pictures
        if relevantImages.count == 1, let image = relevantImages.first {
            appendIfAbsent(.pixels(width: image.pixelWidth, height: image.pixelHeight))
        }
        if let outline = modes.outline, modes.records == nil, modes.cues == nil,
           let count = nodeCount(in: outline) {
            appendIfAbsent(.nodes(count, isLowerBound: isSourcePrefix))
        }
        if isText {
            appendIfAbsent(.encoding(presentation.encoding))
            appendIfAbsent(.lines(presentation.lineCount))
            if let total = presentation.truncatedSourceBytes {
                appendIfAbsent(.shownSize(shown: Int64(presentation.byteCount), total: Int64(total)))
            } else {
                appendIfAbsent(.size(Int64(presentation.byteCount)))
            }
        }
        return PresentationFacts(facts)
    }

    static func facts(for presentation: GeometryPresentation) -> PresentationFacts {
        let mesh = presentation.mesh
        return PresentationFacts([.geometry(faces: mesh.faceCount, bodies: mesh.measurements?.bodyCount,
            extentMillimetres: mesh.bounds.maximum - mesh.bounds.minimum, unit: mesh.unitProvenance,
            facesAreLowerBound: mesh.faceCountIsCapped)] + presentation.facts.facts.filter {
                if case .geometry = $0 { return false }; return true
            })
    }

    /// Called once beside the existing successful listing parse, before its paths become tree nodes.
    static func facts(for listing: SafeListing) -> PresentationFacts {
        var files = 0, folders = 0
        var bytes: Int64? = 0
        for entry in listing.entries {
            if entry.isDirectory { folders += 1; continue }
            files += 1
            guard let current = bytes, let size = entry.bytes, size >= 0 else { bytes = nil; continue }
            let (total, overflow) = current.addingReportingOverflow(size)
            bytes = overflow ? nil : total
        }
        // A directory-only listing provides no file-size measurements to aggregate.
        if files == 0 { bytes = nil }
        return PresentationFacts([.listing(files: files, folders: folders, isLowerBound: listing.isPartial,
            listedBytes: bytes)])
    }

    private static func nodeCount(in roots: [SafeOutlineNode]) -> Int? {
        // Matches the cached safe structure's existing node budget; synthetic oversized models are unknown.
        let maximumNodes = 20_000
        guard roots.count <= maximumNodes else { return nil }
        var pending = roots, count = 0
        while let node = pending.popLast() {
            count += 1
            guard node.children.count <= maximumNodes - count - pending.count else { return nil }
            pending.append(contentsOf: node.children)
        }
        return count
    }

    private enum Family: Equatable {
        case encoding, lines, size, grid, nodes, listing, geometry, playback, pixels
        case records(PresentationFacts.RecordKind)
    }
    private static func family(of fact: PresentationFacts.Fact) -> Family {
        switch fact {
        case .encoding: .encoding
        case .lines: .lines
        case .size, .shownSize: .size
        case .grid: .grid
        case .records(_, let kind, _): .records(kind)
        case .nodes: .nodes
        case .listing: .listing
        case .geometry: .geometry
        case .playback: .playback
        case .pixels: .pixels
        }
    }
}
