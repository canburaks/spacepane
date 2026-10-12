import CoreGraphics
import CoreText
import Foundation
import PreviewContracts

/// Draws thumbnails with Core Graphics, Core Text and decoded ImageIO pictures. It has no AppKit or
/// SwiftUI dependency and no main-actor requirement, so it runs on whatever thread Quick Look uses
/// for the reply's drawing block. Thumbnails are not appearance adaptive: every page is the same
/// light sheet regardless of the system appearance, like the generic glyph.
public enum ThumbnailRenderer {
    // MARK: Generic glyph

    /// The content-free glyph: a light page with three rules. It reads no preference and no file.
    public static func drawGlyph(in context: CGContext, size: CGSize) {
        let unit = min(size.width, size.height)
        let page = ThumbnailPage.rect(in: size, fractions: ThumbnailPage.glyph)
        context.saveGState()
        drawSheet(page, unit: unit, in: context)
        context.setLineWidth(max(unit * 0.025, 1))
        for line in 0..<3 {
            let y = page.midY + CGFloat(line - 1) * unit * 0.11
            context.move(to: CGPoint(x: page.minX + page.width * 0.22, y: y))
            context.addLine(to: CGPoint(x: page.maxX - page.width * 0.22, y: y))
        }
        context.strokePath()
        context.restoreGState()
    }

    // MARK: Content

    public static func draw(_ scene: ThumbnailScene, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let metrics = scene.metrics
        switch scene.content {
        case .picture(let picture):
            drawPicture(picture, metrics: metrics, in: context)
        case .text(let page):
            drawSheet(metrics.page, unit: min(metrics.canvas.width, metrics.canvas.height), in: context)
            clipToSheet(metrics, in: context)
            drawText(page, scene: scene, in: context)
        case .grid(let grid):
            drawSheet(metrics.page, unit: min(metrics.canvas.width, metrics.canvas.height), in: context)
            clipToSheet(metrics, in: context)
            drawGrid(grid, scene: scene, in: context)
        }
    }

    private static let sheetFill = CGColor(gray: 0.96, alpha: 1)
    private static let sheetStroke = CGColor(gray: 0.32, alpha: 1)

    private static func drawSheet(_ page: CGRect, unit: CGFloat, in context: CGContext) {
        context.setFillColor(sheetFill)
        context.setStrokeColor(sheetStroke)
        context.setLineWidth(max(unit * 0.018, 1))
        context.addPath(CGPath(roundedRect: page, cornerWidth: unit * 0.04, cornerHeight: unit * 0.04, transform: nil))
        context.drawPath(using: .fillStroke)
    }

    private static func clipToSheet(_ metrics: ThumbnailMetrics, in context: CGContext) {
        context.clip(to: metrics.textArea.insetBy(dx: -metrics.cellWidth * 0.5, dy: -metrics.lineHeight * 0.25))
    }

    // MARK: Palette

    private static func rgb(_ value: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// The light palette of the app's native renderer, fixed for the light sheet.
    static func color(for tone: ThumbnailTone, usesColor: Bool) -> CGColor {
        let ink = rgb(0x1A1A1A)
        switch tone {
        case .text: return ink
        case .muted: return rgb(0x7A7A7A)
        case .comment: return usesColor ? rgb(0x626262) : rgb(0x6A6A6A)
        default: break
        }
        guard usesColor else { return ink }
        switch tone {
        case .key, .keyword, .tag: return rgb(0x174E94)
        case .string, .addition: return rgb(0x236328)
        case .number: return rgb(0x90430A)
        case .literal, .heading: return rgb(0x6E3288)
        case .deletion: return rgb(0xA02121)
        case .text, .muted, .comment: return ink
        }
    }

    // MARK: Fonts

    private struct Fonts {
        let regular: CTFont
        let bold: CTFont
        let heading: CTFont

        init(size: CGFloat) {
            let base = CTFontCreateUIFontForLanguage(.userFixedPitch, size, nil)
                ?? CTFontCreateWithName("Menlo" as CFString, size, nil)
            regular = base
            bold = CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitBold, .traitBold) ?? base
            let headingSize = size * ThumbnailMetrics.headingScale
            heading = CTFontCreateCopyWithSymbolicTraits(base, headingSize, nil, .traitBold, .traitBold)
                ?? CTFontCreateCopyWithAttributes(base, headingSize, nil, nil)
        }
    }

    private static func drawRun(_ text: String, font: CTFont, color: CGColor, at point: CGPoint, in context: CGContext) {
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        guard let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary) else { return }
        context.textMatrix = .identity
        context.textPosition = point
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
    }

    /// Baseline of a line of `font` that sits at the top of a row of `rowHeight`.
    private static func baseline(top: CGFloat, rowHeight: CGFloat, font: CTFont) -> CGFloat {
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        return top - (rowHeight - (ascent + descent)) / 2 - ascent
    }

    // MARK: Text

    private static func drawText(_ page: ThumbnailTextPage, scene: ThumbnailScene, in context: CGContext) {
        let metrics = scene.metrics
        let fonts = Fonts(size: metrics.fontSize)
        var top = metrics.textArea.maxY
        for line in page.lines {
            let rowHeight = metrics.lineHeight * CGFloat(line.rowCost)
            if top - rowHeight < metrics.textArea.minY - metrics.lineHeight * 0.25 { break }
            let isHeading = line.emphasis == .heading
            let font = isHeading ? fonts.heading : fonts.regular
            let cell = isHeading ? metrics.cellWidth * ThumbnailMetrics.headingScale : metrics.cellWidth
            let y = baseline(top: top, rowHeight: isHeading ? metrics.lineHeight * ThumbnailMetrics.headingScale : metrics.lineHeight, font: font)
            var column = line.indent
            for run in line.runs {
                let origin = CGPoint(x: metrics.textArea.minX + CGFloat(column) * cell, y: y)
                drawRun(run.text, font: font, color: color(for: run.tone, usesColor: scene.usesColor), at: origin, in: context)
                column += ThumbnailCells.width(of: run.text.unicodeScalars)
            }
            top -= rowHeight
        }
    }

    // MARK: Grids

    /// Cell values have no rendering path in a grid: only its header names, typed textures and counts.
    private static func drawGrid(_ grid: ThumbnailGrid, scene: ThumbnailScene, in context: CGContext) {
        let metrics = scene.metrics
        let area = metrics.textArea
        let columns = min(grid.columnCount, ThumbnailGrid.maximumColumns)
        guard columns > 0 else { return }
        let width = area.width / CGFloat(columns)
        let rowHeight = min(area.height * 0.105, max(5 / metrics.pixelScale, metrics.lineHeight))
        let header = CGRect(x: area.minX, y: area.maxY - rowHeight, width: area.width, height: rowHeight)
        context.setFillColor(scene.usesColor ? rgb(0xDCE6ED) : CGColor(gray: 0.87, alpha: 1))
        context.fill(header)
        let fonts = Fonts(size: metrics.fontSize)
        let ink = color(for: .text, usesColor: false)
        for (column, name) in grid.headers.enumerated() where column < columns {
            let cell = CGRect(x: area.minX + CGFloat(column) * width, y: header.minY, width: width, height: rowHeight)
            context.saveGState()
            context.clip(to: cell.insetBy(dx: 2 / metrics.pixelScale, dy: 0))
            let capacity = max(0, Int((width - 4 / metrics.pixelScale) / metrics.cellWidth))
            let text = ThumbnailGridText.clip(name, to: capacity)
            drawRun(text, font: fonts.bold, color: ink,
                    at: CGPoint(x: cell.minX + 2 / metrics.pixelScale,
                                y: baseline(top: header.maxY, rowHeight: rowHeight, font: fonts.bold)), in: context)
            context.restoreGState()
        }
        let visibleRows = min(ThumbnailGrid.maximumSampleRows, grid.rowCount)
        for row in 0..<visibleRows {
            let top = header.minY - CGFloat(row) * rowHeight
            guard top - rowHeight >= area.minY + metrics.lineHeight * 1.5 else { break }
            if row.isMultiple(of: 2) {
                context.setFillColor(CGColor(gray: 0.91, alpha: 1))
                context.fill(CGRect(x: area.minX, y: top - rowHeight, width: area.width, height: rowHeight))
            }
            for column in 0..<columns {
                let kind = column < grid.columnKinds.count ? grid.columnKinds[column] : .unknown
                guard kind != .empty else { continue }
                let cellX = area.minX + CGFloat(column) * width
                let barWidth = width * (kind == .numeric ? 0.38 : kind == .unknown ? 0.42 : 0.62)
                let x = kind == .numeric ? cellX + width * 0.88 - barWidth : cellX + width * 0.12
                context.setFillColor(scene.usesColor && kind == .numeric ? rgb(0x426070) : rgb(0x626262))
                context.fill(CGRect(x: x, y: top - rowHeight * 0.6, width: max(0, barWidth),
                                    height: max(1 / metrics.pixelScale, rowHeight * 0.14)))
            }
        }
        context.setStrokeColor(rgb(0xA0A0A0))
        context.setLineWidth(1 / metrics.pixelScale)
        context.move(to: CGPoint(x: area.minX, y: header.minY))
        context.addLine(to: CGPoint(x: area.maxX, y: header.minY))
        for column in 1..<columns {
            let x = area.minX + CGFloat(column) * width
            context.move(to: CGPoint(x: x, y: header.maxY))
            context.addLine(to: CGPoint(x: x, y: header.minY - CGFloat(visibleRows) * rowHeight))
        }
        context.strokePath()
        guard min(metrics.canvas.width, metrics.canvas.height) * metrics.pixelScale >= 128 else { return }
        // Keep the entire count intact. A very long count line is omitted on a small page instead
        // of clipping an exact total or its lower-bound marker into a misleading number.
        let cells = max(1, ThumbnailCells.width(of: grid.countLine.unicodeScalars))
        let size = min(metrics.fontSize, area.width / (CGFloat(cells) * ThumbnailMetrics.cellAdvanceRatio))
        guard size * metrics.pixelScale >= 7 else { return }
        let font = Fonts(size: size).regular
        drawRun(grid.countLine, font: font, color: rgb(0x626262),
                at: CGPoint(x: area.minX, y: area.minY + CTFontGetDescent(font)), in: context)
    }

    // MARK: Pictures

    private static func drawPicture(_ picture: ThumbnailPicture, metrics: ThumbnailMetrics, in context: CGContext) {
        let canvas = CGRect(origin: .zero, size: metrics.canvas)
        let unit = min(metrics.canvas.width, metrics.canvas.height)
        let imageSize = CGSize(width: picture.image.width, height: picture.image.height)
        context.interpolationQuality = .high
        switch picture.role {
        case .icon:
            let fitted = ThumbnailImageFit.rect(imageSize: imageSize, in: canvas.insetBy(dx: canvas.width * 0.1, dy: canvas.height * 0.1))
            context.draw(picture.image, in: fitted)
        case .cover, .page:
            let fitted = ThumbnailImageFit.rect(imageSize: imageSize, in: canvas.insetBy(dx: canvas.width * 0.04, dy: canvas.height * 0.04))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(fitted)
            context.draw(picture.image, in: fitted)
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.35))
            context.setLineWidth(max(0.5, 0.5 / metrics.pixelScale))
            context.stroke(fitted)
        case .figure:
            drawSheet(metrics.page, unit: unit, in: context)
            let fitted = ThumbnailImageFit.rect(imageSize: imageSize, in: metrics.textArea)
            context.draw(picture.image, in: fitted)
        }
    }
}
