// Render the companion's macOS app icon from the brand mark in Configuration/AppIcon.svg.
//
// usage: xcrun swift script/generate_app_icon.swift [--check]
//
// Configuration/AppIcon.svg is the single icon source. Its rounded square spans
// 2...62 of a 64-unit view box; this places that square on Apple's 1024-pixel macOS
// icon grid (an 824-pixel body inset by 100 pixels) with the standard soft drop
// shadow, then writes every size the Mac App Store asks for into an asset catalog.
// --check verifies the catalog's manifest and image dimensions without writing.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("Configuration/AppIcon.svg")
let catalog = root.appendingPathComponent("Apps/PrevApp/Assets.xcassets")
let iconSet = catalog.appendingPathComponent("AppIcon.appiconset")

/// Grid values are in 1024-pixel canvas units; the brand square occupies 2...62 of 64 source units.
enum Grid {
    static let canvas: CGFloat = 1024
    static let body: CGFloat = 824
    static let inset: CGFloat = 100
    static let sourceSide: CGFloat = 64
    static let sourceBodyOrigin: CGFloat = 2
    static let sourceBodySide: CGFloat = 60
    static let shadowOffset: CGFloat = 10
    static let shadowBlur: CGFloat = 20
    static let shadowAlpha: CGFloat = 0.3
}

struct Slot {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var filename: String { "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png" }
}

let slots = [16, 32, 128, 256, 512].flatMap { points in [1, 2].map { Slot(points: points, scale: $0) } }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func render(_ artwork: NSImage, pixels: Int) -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fail("Could not create a \(pixels)px bitmap") }
    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let unit = CGFloat(pixels) / Grid.canvas
    let scale = Grid.body / Grid.sourceBodySide
    let side = Grid.sourceSide * scale * unit
    let origin = (Grid.inset - Grid.sourceBodyOrigin * scale) * unit
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -Grid.shadowOffset * unit)
    shadow.shadowBlurRadius = Grid.shadowBlur * unit
    shadow.shadowColor = NSColor.black.withAlphaComponent(Grid.shadowAlpha)
    shadow.set()
    artwork.draw(in: NSRect(x: origin, y: origin, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fail("Could not encode a \(pixels)px PNG") }
    return png
}

func manifest() throws -> Data {
    let images = slots.map { ["filename": $0.filename, "idiom": "mac", "scale": "\($0.scale)x", "size": "\($0.points)x\($0.points)"] }
    let object: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
}

func check() throws {
    let written = try JSONSerialization.jsonObject(with: Data(contentsOf: iconSet.appendingPathComponent("Contents.json")))
    let expected = try JSONSerialization.jsonObject(with: manifest())
    guard (written as? NSDictionary) == (expected as? NSDictionary) else { fail("AppIcon manifest drifted; regenerate it") }
    for slot in slots {
        guard let image = NSBitmapImageRep(data: try Data(contentsOf: iconSet.appendingPathComponent(slot.filename))),
              image.pixelsWide == slot.pixels, image.pixelsHigh == slot.pixels else {
            fail("\(slot.filename) is missing or not \(slot.pixels)px; regenerate the icon")
        }
    }
    print("App icon verified: \(slots.count) images in \(iconSet.lastPathComponent).")
}

do {
    if CommandLine.arguments.dropFirst().first == "--check" {
        try check()
        exit(0)
    }
    guard let artwork = NSImage(contentsOf: source) else { fail("Could not load \(source.path)") }
    try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
    try Data(#"{"info":{"author":"xcode","version":1}}"#.utf8).write(to: catalog.appendingPathComponent("Contents.json"))
    for slot in slots {
        try render(artwork, pixels: slot.pixels).write(to: iconSet.appendingPathComponent(slot.filename))
    }
    try manifest().write(to: iconSet.appendingPathComponent("Contents.json"))
    try check()
} catch {
    fail("App icon generation failed: \(error.localizedDescription)")
}
