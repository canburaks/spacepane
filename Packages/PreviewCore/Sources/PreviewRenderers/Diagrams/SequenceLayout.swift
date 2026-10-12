import CoreGraphics
import Foundation

/// Column layout for sequence diagrams: participants are boxes in a row with dashed lifelines,
/// messages and notes stack downward in document order, and frames wrap the items they contain.
/// Gaps between lifelines grow until every message label and note fits between its endpoints.
enum SequenceLayout {
    private static let margin: CGFloat = 24
    private static let maximumParticipantLabelWidth: CGFloat = 160
    private static let maximumMessageLabelWidth: CGFloat = 260
    private static let maximumNoteWidth: CGFloat = 220

    private struct Requirement {
        var from: Int
        var to: Int
        var width: CGFloat
    }

    static func layout(_ model: SequenceDiagramModel, environment: DiagramEnvironment) throws -> DiagramLayoutResult {
        let measurer = DiagramTextMeasurer(font: environment.font)
        let line = measurer.lineHeight
        let count = model.participants.count
        guard count > 0 else { throw DiagramFailure.malformed }

        // Participant boxes.
        let labelLines = model.participants.map { measurer.wrap(DiagramText.lines(from: $0.label), maximumWidth: maximumParticipantLabelWidth) }
        let boxWidths = labelLines.map { max(measurer.size(of: $0).width + 28, 96) }
        let boxHeight = (labelLines.map(\.count).max() ?? 1).asCGFloat * line + 18

        // Message and note text, wrapped once.
        func wrapped(_ text: String, limit: CGFloat) -> [String] {
            measurer.wrap(text.isEmpty ? [] : text.components(separatedBy: "\n"), maximumWidth: limit)
        }
        var messageLines: [Int: [String]] = [:]
        var noteLines: [Int: [String]] = [:]
        for (index, item) in model.items.enumerated() {
            switch item {
            case .message(let message): messageLines[index] = wrapped(message.text, limit: maximumMessageLabelWidth)
            case .note(let note): noteLines[index] = wrapped(note.text, limit: maximumNoteWidth)
            }
        }

        // Horizontal spacing: start from box widths, then widen gaps until every label fits.
        var gaps = (0..<max(count - 1, 0)).map { max((boxWidths[$0] + boxWidths[$0 + 1]) / 2 + 28, 120) }
        var requirements: [Requirement] = []
        var leftNeed: CGFloat = boxWidths[0] / 2
        var rightNeed: CGFloat = boxWidths[count - 1] / 2
        for (index, item) in model.items.enumerated() {
            switch item {
            case .message(let message):
                let width = measurer.size(of: messageLines[index] ?? []).width
                if message.source == message.target {
                    if message.source < count - 1 { requirements.append(.init(from: message.source, to: message.source + 1, width: width + 40)) }
                    else { rightNeed = max(rightNeed, width + 48) }
                } else {
                    requirements.append(.init(from: min(message.source, message.target), to: max(message.source, message.target), width: width + 36))
                }
            case .note(let note):
                let width = measurer.size(of: noteLines[index] ?? []).width + 20
                switch note.placement {
                case .leftOf(let a):
                    if a > 0 { requirements.append(.init(from: a - 1, to: a, width: width + 28)) } else { leftNeed = max(leftNeed, width + 14) }
                case .rightOf(let a):
                    if a < count - 1 { requirements.append(.init(from: a, to: a + 1, width: width + 28)) } else { rightNeed = max(rightNeed, width + 14) }
                case .over(let a, let b):
                    let low = min(a, b), high = max(a, b)
                    if low == high {
                        if low > 0 { requirements.append(.init(from: low - 1, to: low, width: width / 2 + 24)) } else { leftNeed = max(leftNeed, width / 2 + 8) }
                        if low < count - 1 { requirements.append(.init(from: low, to: low + 1, width: width / 2 + 24)) } else { rightNeed = max(rightNeed, width / 2 + 8) }
                    } else {
                        requirements.append(.init(from: low, to: high, width: max(width - 20, 0)))
                    }
                }
            }
        }
        // Short spans first, so a wide label spanning several gaps only adds what is still missing.
        for requirement in requirements.sorted(by: { ($0.to - $0.from, $0.from) < ($1.to - $1.from, $1.from) }) where requirement.to > requirement.from {
            let range = requirement.from..<requirement.to
            let current = gaps[range].reduce(0, +)
            if current < requirement.width {
                let extra = (requirement.width - current) / CGFloat(range.count)
                for index in range { gaps[index] += extra }
            }
        }
        var xs = [CGFloat](repeating: 0, count: count)
        xs[0] = margin + leftNeed
        for index in 1..<max(count, 1) where index < count { xs[index] = xs[index - 1] + gaps[index - 1] }
        let width = xs[count - 1] + rightNeed + margin
        guard width <= DiagramLimits.maximumSceneDimension else { throw DiagramFailure.tooLarge }

        // Vertical placement in document order, with frames opening and closing between items.
        let frameTop = FrameTracker(frames: model.frames)
        var cursor = margin + boxHeight + 22
        var itemY = [CGFloat](repeating: 0, count: model.items.count)
        var frameTops = [CGFloat](repeating: 0, count: model.frames.count)
        var frameBottoms = [CGFloat](repeating: 0, count: model.frames.count)
        var dividerYs: [[CGFloat]] = model.frames.map { Array(repeating: 0, count: $0.dividers.count) }
        for boundary in 0...model.items.count {
            for frame in frameTop.closing(at: boundary) {
                frameBottoms[frame] = cursor
                cursor += 14
            }
            for (frame, divider) in frameTop.dividers(at: boundary, beforeOpening: true) {
                dividerYs[frame][divider] = cursor + 6
                cursor += 28
            }
            for frame in frameTop.opening(at: boundary) {
                frameTops[frame] = cursor
                cursor += 12 + line + 8
            }
            for (frame, divider) in frameTop.dividers(at: boundary, beforeOpening: false) {
                dividerYs[frame][divider] = cursor + 6
                cursor += 28
            }
            guard boundary < model.items.count else { break }
            switch model.items[boundary] {
            case .message(let message):
                let labelHeight = CGFloat(messageLines[boundary]?.count ?? 0) * line
                itemY[boundary] = cursor + labelHeight + 8
                cursor += labelHeight + 8 + (message.source == message.target ? 30 : 10) + 16
            case .note:
                let height = CGFloat(noteLines[boundary]?.count ?? 0) * line + 14
                itemY[boundary] = cursor
                cursor += height + 16
            }
        }
        let bottomBoxTop = cursor + 8
        let height = bottomBoxTop + boxHeight + margin
        guard height <= DiagramLimits.maximumSceneDimension else { throw DiagramFailure.tooLarge }

        var primitives: [DiagramPrimitive] = []
        // Lifelines run behind everything else.
        for index in 0..<count {
            primitives.append(.path(.init(points: [CGPoint(x: xs[index], y: margin + boxHeight), CGPoint(x: xs[index], y: bottomBoxTop)],
                                          line: .dashed, startHead: .none, endHead: .none)))
        }

        // Frames.
        let nestingHeight = FrameTracker.nestingHeights(model.frames)
        for (index, frame) in model.frames.enumerated() {
            var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
            for item in frame.firstItem..<frame.endItem {
                let extent = horizontalExtent(of: model.items[item], xs: xs, measurer: measurer,
                                              messageLines: messageLines[item] ?? [], noteLines: noteLines[item] ?? [])
                minX = min(minX, extent.lowerBound)
                maxX = max(maxX, extent.upperBound)
            }
            if minX > maxX { minX = xs[0] - 40; maxX = xs[count - 1] + 40 }
            let padding = 14 + 8 * CGFloat(nestingHeight[index])
            let rect = CGRect(x: minX - padding, y: frameTops[index], width: maxX - minX + padding * 2,
                              height: max(frameBottoms[index] - frameTops[index] + 4, line + 20))
            let title = frame.label.isEmpty ? frame.keyword : frame.keyword + " [" + frame.label + "]"
            primitives.append(.frame(.init(rect: rect, title: title, isDashed: false, fill: .none)))
            for (position, divider) in frame.dividers.enumerated() {
                let y = dividerYs[index][position]
                primitives.append(.path(.init(points: [CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y)],
                                              line: .dashed, startHead: .none, endHead: .none)))
                if !divider.label.isEmpty {
                    let lines = measurer.wrap([ "[" + divider.label + "]" ], maximumWidth: rect.width - 16)
                    primitives.append(.text(.init(lines: lines, rect: CGRect(x: rect.minX + 8, y: y + 2, width: rect.width - 16, height: CGFloat(lines.count) * line),
                                                  alignment: .leading, verticalAlignment: .top)))
                }
            }
        }

        // Participant boxes at both ends of the lifelines.
        var accessibility: [DiagramAccessibilityNode] = []
        for (index, participant) in model.participants.enumerated() {
            for top in [margin, bottomBoxTop] {
                let rect = CGRect(x: xs[index] - boxWidths[index] / 2, y: top, width: boxWidths[index], height: boxHeight)
                primitives.append(.shape(.init(rect: rect, shape: participant.isActor ? .rounded : .rectangle, fill: .node, lines: labelLines[index])))
                if top == margin {
                    accessibility.append(.init(label: labelLines[index].joined(separator: " "), role: .participant, rect: rect))
                }
            }
        }

        // Messages and notes.
        var connections: [DiagramConnection] = []
        for (index, item) in model.items.enumerated() {
            switch item {
            case .message(let message):
                let y = itemY[index]
                let sourceX = xs[message.source], targetX = xs[message.target]
                let lines = messageLines[index] ?? []
                if message.source == message.target {
                    let points = [CGPoint(x: sourceX, y: y), CGPoint(x: sourceX + 32, y: y), CGPoint(x: sourceX + 32, y: y + 22), CGPoint(x: sourceX, y: y + 22)]
                    primitives.append(.path(.init(points: points, line: message.line, startHead: message.startHead, endHead: message.head)))
                    if !lines.isEmpty {
                        let size = measurer.size(of: lines)
                        primitives.append(.text(.init(lines: lines, rect: CGRect(x: sourceX + 6, y: y - size.height - 2, width: size.width + 4, height: size.height),
                                                      alignment: .leading)))
                    }
                } else {
                    primitives.append(.path(.init(points: [CGPoint(x: sourceX, y: y), CGPoint(x: targetX, y: y)],
                                                  line: message.line, startHead: message.startHead, endHead: message.head)))
                    if !lines.isEmpty {
                        let size = measurer.size(of: lines)
                        let center = (sourceX + targetX) / 2
                        primitives.append(.text(.init(lines: lines, rect: CGRect(x: center - size.width / 2 - 2, y: y - size.height - 2, width: size.width + 4, height: size.height))))
                    }
                }
                connections.append(.init(source: model.participants[message.source].label, target: model.participants[message.target].label,
                                         label: message.text.isEmpty ? nil : DiagramText.singleLine(from: message.text)))
            case .note(let note):
                let lines = noteLines[index] ?? []
                let size = measurer.size(of: lines)
                let noteWidth = size.width + 20, noteHeight = size.height + 14
                let x: CGFloat
                var finalWidth = noteWidth
                switch note.placement {
                case .leftOf(let a): x = xs[a] - 12 - noteWidth
                case .rightOf(let a): x = xs[a] + 12
                case .over(let a, let b):
                    let low = xs[min(a, b)], high = xs[max(a, b)]
                    finalWidth = max(noteWidth, high - low + 20)
                    x = (low + high) / 2 - finalWidth / 2
                }
                primitives.append(.shape(.init(rect: CGRect(x: x, y: itemY[index], width: finalWidth, height: noteHeight), shape: .note, fill: .note, lines: lines)))
            }
        }
        return DiagramLayoutResult(scene: DiagramScene(size: CGSize(width: width, height: height), primitives: primitives),
                                   nodes: accessibility, connections: connections)
    }

    private static func horizontalExtent(of item: SequenceDiagramModel.Item, xs: [CGFloat], measurer: DiagramTextMeasurer,
                                         messageLines: [String], noteLines: [String]) -> ClosedRange<CGFloat> {
        switch item {
        case .message(let message):
            if message.source == message.target {
                let labelWidth = measurer.size(of: messageLines).width
                return (xs[message.source] - 4)...(xs[message.source] + max(36, labelWidth + 10))
            }
            return min(xs[message.source], xs[message.target])...max(xs[message.source], xs[message.target])
        case .note(let note):
            let width = measurer.size(of: noteLines).width + 20
            switch note.placement {
            case .leftOf(let a): return (xs[a] - 12 - width)...(xs[a] - 12)
            case .rightOf(let a): return (xs[a] + 12)...(xs[a] + 12 + width)
            case .over(let a, let b):
                let low = xs[min(a, b)], high = xs[max(a, b)]
                let finalWidth = max(width, high - low + 20)
                let center = (low + high) / 2
                return (center - finalWidth / 2)...(center + finalWidth / 2)
            }
        }
    }
}

private extension Int {
    var asCGFloat: CGFloat { CGFloat(self) }
}

/// Orders frame openings, closings and dividers between the items of a sequence diagram.
private struct FrameTracker {
    let frames: [SequenceDiagramModel.Frame]

    /// Frames closing at `boundary`, innermost first (they were recorded in closing order).
    func closing(at boundary: Int) -> [Int] {
        frames.indices.filter { frames[$0].endItem == boundary }
    }

    /// Frames opening at `boundary`, outermost first.
    func opening(at boundary: Int) -> [Int] {
        frames.indices.filter { frames[$0].firstItem == boundary }.reversed()
    }

    /// Dividers before the item at `boundary`: those of frames already open come before new frames
    /// open, those of a frame opening here come after it.
    func dividers(at boundary: Int, beforeOpening: Bool) -> [(frame: Int, divider: Int)] {
        var result: [(Int, Int)] = []
        for (frameIndex, frame) in frames.enumerated() {
            for (dividerIndex, divider) in frame.dividers.enumerated() where divider.beforeItem == boundary {
                let opensHere = frame.firstItem == boundary
                if opensHere != beforeOpening { result.append((frameIndex, dividerIndex)) }
            }
        }
        return result
    }

    /// How many levels of frames sit inside each frame, so outer frames can be drawn wider.
    static func nestingHeights(_ frames: [SequenceDiagramModel.Frame]) -> [Int] {
        var heights = [Int](repeating: 0, count: frames.count)
        for outer in frames.indices {
            for inner in 0..<outer where frames[outer].firstItem <= frames[inner].firstItem && frames[inner].endItem <= frames[outer].endItem {
                heights[outer] = max(heights[outer], heights[inner] + 1)
            }
        }
        return heights
    }
}
