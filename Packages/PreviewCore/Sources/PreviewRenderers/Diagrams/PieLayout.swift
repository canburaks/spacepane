import CoreGraphics
import Foundation

/// Pie geometry: slices in descending order from twelve o'clock, clockwise, with a legend.
enum PieLayout {
    private static let margin: CGFloat = 24
    private static let radius: CGFloat = 120
    private static let maximumLegendLabelWidth: CGFloat = 260

    static func layout(_ model: PieDiagramModel, environment: DiagramEnvironment) throws -> DiagramLayoutResult {
        let measurer = DiagramTextMeasurer(font: environment.font)
        let line = measurer.lineHeight
        // Larger slices first, as Mermaid draws them; equal values keep their document order.
        let ordered = model.slices.enumerated().filter { $0.element.value > 0 }
            .sorted { $0.element.value != $1.element.value ? $0.element.value > $1.element.value : $0.offset < $1.offset }
            .map(\.element)
        let total = ordered.reduce(0) { $0 + $1.value }
        guard total > 0, total.isFinite, !ordered.isEmpty else { throw DiagramFailure.malformed }

        var primitives: [DiagramPrimitive] = []
        var accessibility: [DiagramAccessibilityNode] = []
        var top = margin
        var titleWidth: CGFloat = 0
        var titleLines: [String] = []
        if let title = model.title, !title.isEmpty {
            titleLines = measurer.wrap([title], maximumWidth: radius * 2 + 240, bold: true)
            titleWidth = measurer.size(of: titleLines, bold: true).width
            top += CGFloat(titleLines.count) * line + 14
        }
        let center = CGPoint(x: margin + radius, y: top + radius)
        let percent = FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0)).locale(environment.locale)

        var angle = -Double.pi / 2
        for (index, slice) in ordered.enumerated() {
            let fraction = slice.value / total
            let end = angle + fraction * 2 * Double.pi
            primitives.append(.slice(.init(center: center, radius: radius, startAngle: angle, endAngle: end, colorIndex: index)))
            let middle = (angle + end) / 2
            if fraction >= 0.04 {
                let label = fraction.formatted(percent)
                let size = measurer.size(of: [label])
                let anchor = CGPoint(x: center.x + CGFloat(cos(middle)) * radius * 0.66, y: center.y + CGFloat(sin(middle)) * radius * 0.66)
                primitives.append(.text(.init(lines: [label], rect: CGRect(x: anchor.x - size.width / 2 - 3, y: anchor.y - size.height / 2 - 1,
                                                                            width: size.width + 6, height: size.height + 2),
                                              hasBackground: true, isSmall: true)))
            }
            accessibility.append(.init(label: PreviewStrings.format(.diagramSliceLabel, arguments: [slice.label, fraction.formatted(percent)],
                                                                    locale: environment.locale),
                                       role: .slice, rect: wedgeBounds(center: center, start: angle, end: end)))
            angle = end
        }

        // Legend to the right of the pie.
        let legendX = margin + radius * 2 + 32
        var legendY = center.y - radius
        var legendWidth: CGFloat = 0
        for (index, slice) in ordered.enumerated() {
            let text = model.showsData ? slice.label + " [" + slice.valueText + "]" : slice.label
            let lines = measurer.wrap([text], maximumWidth: maximumLegendLabelWidth)
            let size = measurer.size(of: lines)
            let rowHeight = max(size.height, 16) + 8
            primitives.append(.swatch(.init(rect: CGRect(x: legendX, y: legendY + (rowHeight - 16) / 2 - 2, width: 16, height: 16), colorIndex: index)))
            primitives.append(.text(.init(lines: lines, rect: CGRect(x: legendX + 24, y: legendY, width: size.width + 4, height: rowHeight - 4),
                                          alignment: .leading, verticalAlignment: .middle)))
            legendWidth = max(legendWidth, size.width + 28)
            legendY += rowHeight
        }
        if !titleLines.isEmpty {
            let contentWidth = radius * 2 + 32 + legendWidth
            let size = measurer.size(of: titleLines, bold: true)
            primitives.append(.text(.init(lines: titleLines, rect: CGRect(x: margin + (contentWidth - size.width) / 2, y: margin,
                                                                           width: size.width, height: size.height),
                                          isBold: true)))
        }
        let width = max(margin * 2 + radius * 2 + 32 + legendWidth, margin * 2 + titleWidth)
        let height = max(center.y + radius, legendY) + margin
        return DiagramLayoutResult(scene: DiagramScene(size: CGSize(width: width, height: height), primitives: primitives),
                                   nodes: accessibility, connections: [])
    }

    /// Bounding box of the wedge between two angles, for accessibility frames.
    private static func wedgeBounds(center: CGPoint, start: Double, end: Double) -> CGRect {
        var points = [center]
        let steps = max(2, Int(((end - start) / (Double.pi / 12)).rounded(.up)))
        for step in 0...steps {
            let angle = start + (end - start) * Double(step) / Double(steps)
            points.append(CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius))
        }
        return points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }
}
