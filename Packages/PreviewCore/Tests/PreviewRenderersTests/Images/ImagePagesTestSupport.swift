import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers
import PreviewContracts
@testable import PreviewRenderers

/// A solid RGBA bitmap, standing in for a decoded page.
func testBitmap(width: Int, height: Int) -> CGImage {
    let context = CGContext(data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

/// A tiny encoded PNG for building `PreviewImage`s in tests.
func testPNG(_ width: Int, _ height: Int) -> Data {
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, testBitmap(width: width, height: height), nil)
    precondition(CGImageDestinationFinalize(destination))
    return output as Data
}

func testPages(_ count: Int, width: Int = 100, height: Int = 140, role: PreviewImage.Role = .page) -> [PreviewImage] {
    (0..<count).map { PreviewImage(data: Data("page-\($0)".utf8), pixelWidth: width, pixelHeight: height, role: role) }
}

/// Records how decodes overlap and which sizes were requested; an optional gate holds every decode open.
final class DecodeProbe: Sendable {
    private struct State { var running = 0, maximum = 0, started = 0, finished = 0, gateOpen = true; var sizes: [Int] = [] }
    private let state = Mutex(State())

    init(gated: Bool = false) { state.withLock { $0.gateOpen = !gated } }

    var maximumConcurrent: Int { state.withLock { $0.maximum } }
    var started: Int { state.withLock { $0.started } }
    var finished: Int { state.withLock { $0.finished } }
    var requestedSizes: [Int] { state.withLock { $0.sizes } }
    func open() { state.withLock { $0.gateOpen = true } }

    /// A scheduler decode closure that yields bitmaps with the requested longer side and the pages' 100:140 aspect.
    func decode() -> ImagePageScheduler.Decode {
        { [self] data, size in
            state.withLock { $0.running += 1; $0.maximum = max($0.maximum, $0.running); $0.started += 1; $0.sizes.append(size) }
            while !state.withLock({ $0.gateOpen }) {
                if Task.isCancelled { break }
                try? await Task.sleep(for: .milliseconds(2))
            }
            let cancelled = Task.isCancelled
            state.withLock { $0.running -= 1; $0.finished += 1 }
            if cancelled { return nil }
            let width = max(1, size * 100 / 140)
            return DecodedPageImage(image: testBitmap(width: width, height: size))
        }
    }
}

/// Polls the main actor until `condition` holds; the decode tasks hop back to it to deliver results.
@MainActor
func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

@MainActor
func testStyle(locale: Locale = Locale(identifier: "en")) -> SafeModeStyle {
    SafeModeStyle(typography: PreviewTypography(), palette: NativeTextPalette(theme: .light, isDark: false, increasedContrast: false),
                  syntaxStyle: PreviewSyntaxStyle(), locale: locale)
}

func keyEvent(_ keyCode: UInt16, characters: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                     characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
}

func presentation(_ formatID: FormatID, text: String = "", syntax: TextSyntax = .plain, images: [PreviewImage] = []) -> TextPresentation {
    TextPresentation(formatID: formatID, text: text, lineCount: max(1, text.components(separatedBy: "\n").count), byteCount: text.utf8.count,
                     encoding: .utf8, redactionCount: 0, syntax: syntax, images: images)
}
