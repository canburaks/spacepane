import CoreGraphics
import CoreText
import Foundation

/// Draws a `DiagramScene` into a Core Graphics context. The context's current transform must map
/// scene coordinates (origin top-left, y down) to the device, so one routine serves the zoomable
/// view, a Markdown figure and a thumbnail. Text uses Core Text, and nothing here depends on
/// AppKit or the main actor.
enum DiagramDrawing {
    private struct Fonts {
        let regular: CTFont
        let bold: CTFont
        let small: CTFont
        let lineHeight: CGFloat
        let smallLineHeight: CGFloat

        init(_ font: DiagramFont) {
            regular = font.ctFont()
            bold = font.ctFont(bold: true)
            small = font.ctFont(size: font.smallPointSize)
            lineHeight = DiagramTextMeasurer.lineHeight(of: regular)
            smallLineHeight = DiagramTextMeasurer.lineHeight(of: small)
        }
    }

    /// Draws every primitive that intersects `visibleRect` (scene coordinates; nil draws all).
    static func draw(_ scene: DiagramScene, in context: CGContext, palette: DiagramPalette, font: DiagramFont,
                     visibleRect: CGRect? = nil) {
        let fonts = Fonts(font)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        for primitive in scene.primitives {
            if let visibleRect, !primitive.bounds.intersects(visibleRect) { continue }
            switch primitive {
            case .frame(let item): drawFrame(item, context, palette, fonts)
            case .shape(let item): drawShape(item, context, palette, fonts)
            case .path(let item): drawPath(item, context, palette)
            case .text(let item): drawTextItem(item, context, palette, fonts)
            case .slice(let item): drawSlice(item, context, palette)
            case .swatch(let item): drawSwatch(item, context, palette)
            }
        }
    }

    // MARK: Frames and shapes

    private static func drawFrame(_ item: DiagramFrameItem, _ context: CGContext, _ palette: DiagramPalette, _ fonts: Fonts) {
        context.saveGState()
        let path = CGPath(roundedRect: item.rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        if item.fill != .none {
            context.setFillColor(palette.frameFill.cgColor)
            context.addPath(path)
            context.fillPath()
        }
        context.setStrokeColor(palette.frameStroke.cgColor)
        context.setLineWidth(palette.strokeWidth)
        if item.isDashed { context.setLineDash(phase: 0, lengths: [6, 4]) }
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
        if let title = item.title, !title.isEmpty {
            drawLines([title], in: CGRect(x: item.rect.minX + 10, y: item.rect.minY + 4, width: max(item.rect.width - 20, 1), height: fonts.lineHeight),
                      alignment: .leading, vertical: .top, bold: true, small: false, color: palette.foreground.cgColor, fonts: fonts, context: context)
        }
    }

    private static func drawShape(_ item: DiagramShapeItem, _ context: CGContext, _ palette: DiagramPalette, _ fonts: Fonts) {
        let rect = item.rect
        var textRect = rect.insetBy(dx: 6, dy: 3)
        context.saveGState()
        context.setLineWidth(palette.strokeWidth)
        context.setStrokeColor(palette.nodeStroke.cgColor)
        if item.isDashed { context.setLineDash(phase: 0, lengths: [6, 4]) }
        var fillColor: CGColor?
        switch item.fill {
        case .node: fillColor = palette.nodeFill.cgColor
        case .note: fillColor = palette.noteFill.cgColor
        case .frame: fillColor = palette.frameFill.cgColor
        case .solid: fillColor = palette.foreground.cgColor
        case .none: fillColor = nil
        }
        func fillAndStroke(_ path: CGPath) {
            if let fillColor { context.setFillColor(fillColor); context.addPath(path); context.fillPath() }
            if item.hasOutline { context.addPath(path); context.strokePath() }
        }
        switch item.shape {
        case .textOnly:
            break
        case .rectangle:
            fillAndStroke(CGPath(rect: rect, transform: nil))
        case .rounded:
            fillAndStroke(CGPath(roundedRect: rect, cornerWidth: min(8, rect.height / 2), cornerHeight: min(8, rect.height / 2), transform: nil))
        case .stadium:
            fillAndStroke(CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
        case .circle, .ellipse:
            fillAndStroke(CGPath(ellipseIn: rect, transform: nil))
        case .doubleCircle:
            fillAndStroke(CGPath(ellipseIn: rect, transform: nil))
            context.addPath(CGPath(ellipseIn: rect.insetBy(dx: 5, dy: 5), transform: nil))
            context.strokePath()
        case .diamond:
            fillAndStroke(polygon([CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
                                   CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)]))
            textRect = rect.insetBy(dx: rect.width * 0.2, dy: rect.height * 0.15)
        case .triangle:
            fillAndStroke(polygon([CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]))
            textRect = CGRect(x: rect.minX + rect.width * 0.25, y: rect.midY, width: rect.width * 0.5, height: rect.height / 2)
        case .hexagon:
            let inset = min(rect.height * 0.3, rect.width * 0.2)
            fillAndStroke(polygon([CGPoint(x: rect.minX + inset, y: rect.minY), CGPoint(x: rect.maxX - inset, y: rect.minY),
                                   CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.maxX - inset, y: rect.maxY),
                                   CGPoint(x: rect.minX + inset, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)]))
        case .parallelogram:
            let skew = min(14, rect.width / 4)
            fillAndStroke(polygon([CGPoint(x: rect.minX + skew, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                                   CGPoint(x: rect.maxX - skew, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]))
        case .asymmetric:
            let notch = min(12, rect.width / 4)
            fillAndStroke(polygon([CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                                   CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
                                   CGPoint(x: rect.minX + notch, y: rect.midY)]))
        case .subroutine:
            fillAndStroke(CGPath(rect: rect, transform: nil))
            for x in [rect.minX + 8, rect.maxX - 8] {
                context.move(to: CGPoint(x: x, y: rect.minY)); context.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            context.strokePath()
        case .cylinder:
            let ry = min(8, rect.height / 4)
            fillAndStroke(cylinderPath(rect, ry: ry))
            context.addPath(CGPath(ellipseIn: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: ry * 2), transform: nil))
            context.strokePath()
            textRect = CGRect(x: rect.minX + 4, y: rect.minY + ry * 2, width: rect.width - 8, height: rect.height - ry * 3)
        case .note:
            let fold = min(10, rect.height / 3, rect.width / 3)
            fillAndStroke(polygon([rect.origin, CGPoint(x: rect.maxX - fold, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY + fold),
                                   CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]))
            context.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY + fold))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
            context.strokePath()
        case .startMarker:
            context.setFillColor(palette.foreground.cgColor)
            context.fillEllipse(in: rect)
        case .endMarker:
            context.setFillColor(palette.background.cgColor)
            context.fillEllipse(in: rect)
            context.setLineWidth(palette.strokeWidth)
            context.setStrokeColor(palette.foreground.cgColor)
            context.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
            context.setFillColor(palette.foreground.cgColor)
            context.fillEllipse(in: rect.insetBy(dx: 5, dy: 5))
        case .bar:
            context.setFillColor(palette.foreground.cgColor)
            context.fill(rect)
        case .record:
            fillAndStroke(CGPath(rect: rect, transform: nil))
            var top = rect.minY
            for (index, count) in item.compartments.enumerated() {
                if index > 0 {
                    context.move(to: CGPoint(x: rect.minX, y: top))
                    context.addLine(to: CGPoint(x: rect.maxX, y: top))
                    context.strokePath()
                }
                top += CGFloat(count) * fonts.lineHeight + 8
            }
        case .swimlane(let header, let leftHeader):
            fillAndStroke(CGPath(rect: rect, transform: nil))
            let band = leftHeader ? CGRect(x: rect.minX, y: rect.minY, width: min(header, rect.width), height: rect.height)
                                  : CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(header, rect.height))
            context.setFillColor(palette.frameFill.cgColor)
            context.fill(band)
            context.addPath(CGPath(rect: band, transform: nil))
            context.strokePath()
            textRect = band.insetBy(dx: 4, dy: 1)
        }
        context.restoreGState()
        guard !item.lines.isEmpty else { return }
        if item.shape == .record {
            drawRecordText(item, context, palette, fonts)
            return
        }
        var color = palette.foreground.cgColor
        if case .solid = item.fill { color = palette.background.cgColor }
        drawLines(item.lines, in: textRect, alignment: item.alignment, vertical: item.verticalAlignment, bold: item.isBold,
                  small: false, color: color, fonts: fonts, context: context)
    }

    /// The header compartment is centered and bold; member compartments are left aligned.
    private static func drawRecordText(_ item: DiagramShapeItem, _ context: CGContext, _ palette: DiagramPalette, _ fonts: Fonts) {
        var top = item.rect.minY
        var first = 0
        for (index, count) in item.compartments.enumerated() {
            let lines = Array(item.lines[min(first, item.lines.count)..<min(first + count, item.lines.count)])
            let box = CGRect(x: item.rect.minX + (index == 0 ? 6 : 10), y: top + 4, width: max(item.rect.width - (index == 0 ? 12 : 20), 1),
                             height: CGFloat(count) * fonts.lineHeight)
            drawLines(lines, in: box, alignment: index == 0 ? .center : .leading, vertical: .top, bold: index == 0, small: false,
                      color: palette.foreground.cgColor, fonts: fonts, context: context)
            top += CGFloat(count) * fonts.lineHeight + 8
            first += count
        }
    }

    private static func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    private static func cylinderPath(_ rect: CGRect, ry: CGFloat) -> CGPath {
        let k: CGFloat = 0.5523
        let cx = rect.midX, rx = rect.width / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + ry))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - ry))
        path.addCurve(to: CGPoint(x: cx, y: rect.maxY), control1: CGPoint(x: rect.minX, y: rect.maxY - ry + k * ry),
                      control2: CGPoint(x: cx - k * rx, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - ry), control1: CGPoint(x: cx + k * rx, y: rect.maxY),
                      control2: CGPoint(x: rect.maxX, y: rect.maxY - ry + k * ry))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + ry))
        path.addCurve(to: CGPoint(x: cx, y: rect.minY), control1: CGPoint(x: rect.maxX, y: rect.minY + ry - k * ry),
                      control2: CGPoint(x: cx + k * rx, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + ry), control1: CGPoint(x: cx - k * rx, y: rect.minY),
                      control2: CGPoint(x: rect.minX, y: rect.minY + ry - k * ry))
        path.closeSubpath()
        return path
    }

    // MARK: Paths and arrowheads

    private static let arrowLength: CGFloat = 10

    private static func drawPath(_ item: DiagramPathItem, _ context: CGContext, _ palette: DiagramPalette) {
        guard item.points.count >= 2 else { return }
        var points = item.points
        // Filled heads cover the end of the line, which stops at the head's base.
        if let trim = baseOffset(item.endHead) { points[points.count - 1] = moved(points[points.count - 1], toward: points[points.count - 2], by: trim) }
        if let trim = baseOffset(item.startHead) { points[0] = moved(points[0], toward: points[1], by: trim) }
        context.saveGState()
        context.setStrokeColor(palette.edge.cgColor)
        context.setFillColor(palette.edge.cgColor)
        context.setLineWidth(palette.strokeWidth * (item.line == .thick ? 2 : 1))
        switch item.line {
        case .dashed: context.setLineDash(phase: 0, lengths: [6, 4])
        case .dotted: context.setLineDash(phase: 0, lengths: [1.5, 4])
        case .solid, .thick: break
        }
        context.addPath(roundedPolyline(points, radius: 8))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
        context.setLineWidth(palette.strokeWidth)
        if let last = item.points.last, let before = item.points.dropLast().last(where: { $0 != last }) {
            drawHead(item.endHead, at: last, from: before, context, palette)
        }
        if let first = item.points.first, let after = item.points.dropFirst().first(where: { $0 != first }) {
            drawHead(item.startHead, at: first, from: after, context, palette)
        }
        context.restoreGState()
    }

    /// How far a head reaches along the line; the stroke stops there so it does not show through a hollow head.
    private static func baseOffset(_ head: DiagramArrowhead) -> CGFloat? {
        switch head {
        case .arrow: arrowLength - 1
        case .hollowTriangle: 11
        case .diamond, .filledDiamond: 13
        default: nil
        }
    }

    private static func moved(_ point: CGPoint, toward other: CGPoint, by distance: CGFloat) -> CGPoint {
        let length = hypot(other.x - point.x, other.y - point.y)
        guard length > distance else { return point }
        return CGPoint(x: point.x + (other.x - point.x) / length * distance, y: point.y + (other.y - point.y) / length * distance)
    }

    private static func roundedPolyline(_ points: [CGPoint], radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 1..<points.count {
            let current = points[index]
            guard index < points.count - 1 else { path.addLine(to: current); break }
            let previous = points[index - 1], next = points[index + 1]
            let before = hypot(previous.x - current.x, previous.y - current.y)
            let after = hypot(next.x - current.x, next.y - current.y)
            guard before > 0, after > 0 else { continue }
            let r = min(radius, before / 2, after / 2)
            path.addLine(to: CGPoint(x: current.x + (previous.x - current.x) / before * r, y: current.y + (previous.y - current.y) / before * r))
            path.addQuadCurve(to: CGPoint(x: current.x + (next.x - current.x) / after * r, y: current.y + (next.y - current.y) / after * r),
                              control: current)
        }
        return path
    }

    private static func drawHead(_ head: DiagramArrowhead, at tip: CGPoint, from origin: CGPoint, _ context: CGContext, _ palette: DiagramPalette) {
        guard head != .none else { return }
        let length = max(hypot(tip.x - origin.x, tip.y - origin.y), 0.001)
        let ux = (tip.x - origin.x) / length, uy = (tip.y - origin.y) / length
        let nx = -uy, ny = ux
        func point(_ back: CGFloat, _ side: CGFloat) -> CGPoint {
            CGPoint(x: tip.x - ux * back + nx * side, y: tip.y - uy * back + ny * side)
        }
        switch head {
        case .none: break
        case .arrow:
            context.addPath(polygon([tip, point(arrowLength, 4.5), point(arrowLength, -4.5)]))
            context.fillPath()
        case .open:
            context.move(to: point(arrowLength, 5)); context.addLine(to: tip); context.addLine(to: point(arrowLength, -5))
            context.strokePath()
        case .circle:
            let center = point(5, 0)
            context.setFillColor(palette.background.cgColor)
            context.addEllipse(in: CGRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9))
            context.drawPath(using: .fillStroke)
            context.setFillColor(palette.edge.cgColor)
        case .cross:
            context.move(to: point(1, 5)); context.addLine(to: point(11, -5))
            context.move(to: point(1, -5)); context.addLine(to: point(11, 5))
            context.strokePath()
        case .diamond:
            context.setFillColor(palette.background.cgColor)
            context.addPath(polygon([tip, point(7, 4.5), point(14, 0), point(7, -4.5)]))
            context.drawPath(using: .fillStroke)
            context.setFillColor(palette.edge.cgColor)
        case .filledDiamond:
            context.addPath(polygon([tip, point(7, 4.5), point(14, 0), point(7, -4.5)]))
            context.fillPath()
        case .hollowTriangle:
            context.setFillColor(palette.background.cgColor)
            context.addPath(polygon([tip, point(12, 6), point(12, -6)]))
            context.drawPath(using: .fillStroke)
            context.setFillColor(palette.edge.cgColor)
        case .exactlyOne:
            for distance: CGFloat in [6, 11] {
                context.move(to: point(distance, 5)); context.addLine(to: point(distance, -5))
            }
            context.strokePath()
        case .zeroOrOne:
            context.move(to: point(6, 5)); context.addLine(to: point(6, -5))
            context.strokePath()
            let center = point(14, 0)
            context.setFillColor(palette.background.cgColor)
            context.addEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            context.drawPath(using: .fillStroke)
            context.setFillColor(palette.edge.cgColor)
        case .oneOrMore, .zeroOrMore:
            // Crow's foot: three prongs meet on the line and spread at the entity's border.
            context.move(to: point(12, 0)); context.addLine(to: point(0, 6))
            context.move(to: point(12, 0)); context.addLine(to: point(0, -6))
            context.move(to: point(12, 0)); context.addLine(to: tip)
            context.strokePath()
            if head == .oneOrMore {
                context.move(to: point(15, 5)); context.addLine(to: point(15, -5))
                context.strokePath()
            } else {
                let center = point(18, 0)
                context.setFillColor(palette.background.cgColor)
                context.addEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
                context.drawPath(using: .fillStroke)
                context.setFillColor(palette.edge.cgColor)
            }
        }
    }

    // MARK: Text

    private static func drawTextItem(_ item: DiagramTextItem, _ context: CGContext, _ palette: DiagramPalette, _ fonts: Fonts) {
        if item.hasBackground {
            context.setFillColor(palette.labelBackground.cgColor)
            context.addPath(CGPath(roundedRect: item.rect, cornerWidth: 4, cornerHeight: 4, transform: nil))
            context.fillPath()
        }
        drawLines(item.lines, in: item.rect, alignment: item.alignment, vertical: item.verticalAlignment, bold: item.isBold,
                  small: item.isSmall, color: palette.foreground.cgColor, fonts: fonts, context: context)
    }

    private static func drawLines(_ lines: [String], in rect: CGRect, alignment: DiagramTextAlignment, vertical: DiagramVerticalAlignment,
                                  bold: Bool, small: Bool, color: CGColor, fonts: Fonts, context: CGContext) {
        guard !lines.isEmpty else { return }
        let font = small ? fonts.small : bold ? fonts.bold : fonts.regular
        let lineHeight = small ? fonts.smallLineHeight : fonts.lineHeight
        let block = lineHeight * CGFloat(lines.count)
        let top: CGFloat
        switch vertical {
        case .top: top = rect.minY
        case .middle: top = rect.midY - block / 2
        case .bottom: top = rect.maxY - block
        }
        context.saveGState()
        // Scene coordinates run downward, so glyphs are flipped back upright.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
        for (index, text) in lines.enumerated() where !text.isEmpty {
            guard let attributed = CFAttributedStringCreate(nil, text as CFString, attributes) else { continue }
            let line = CTLineCreateWithAttributedString(attributed)
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let x: CGFloat
            switch alignment {
            case .leading: x = rect.minX
            case .center: x = rect.midX - width / 2
            case .trailing: x = rect.maxX - width
            }
            context.textPosition = CGPoint(x: x, y: top + lineHeight * CGFloat(index) + ceil(CTFontGetAscent(font)) + 1)
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }

    // MARK: Pie

    private static func drawSlice(_ item: DiagramSliceItem, _ context: CGContext, _ palette: DiagramPalette) {
        let span = item.endAngle - item.startAngle
        let steps = max(2, Int((abs(span) / (Double.pi / 90)).rounded(.up)))
        var points = [item.center]
        for step in 0...steps {
            let angle = item.startAngle + span * Double(step) / Double(steps)
            points.append(CGPoint(x: item.center.x + CGFloat(cos(angle)) * item.radius, y: item.center.y + CGFloat(sin(angle)) * item.radius))
        }
        context.saveGState()
        context.setFillColor(palette.sliceColor(index: item.colorIndex).cgColor)
        context.setStrokeColor(palette.background.cgColor)
        context.setLineWidth(max(palette.strokeWidth, 1.5))
        context.addPath(polygon(points))
        context.drawPath(using: .fillStroke)
        context.restoreGState()
    }

    private static func drawSwatch(_ item: DiagramSwatchItem, _ context: CGContext, _ palette: DiagramPalette) {
        context.saveGState()
        context.setFillColor(palette.sliceColor(index: item.colorIndex).cgColor)
        context.setStrokeColor(palette.nodeStroke.cgColor)
        context.setLineWidth(max(palette.strokeWidth * 0.75, 1))
        context.addPath(CGPath(roundedRect: item.rect, cornerWidth: 3, cornerHeight: 3, transform: nil))
        context.drawPath(using: .fillStroke)
        context.restoreGState()
    }
}
