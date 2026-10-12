import Foundation
import Testing
import UniformTypeIdentifiers
import PreviewContracts
@testable import PreviewFormats

@Suite("Embedded image validation")
struct EmbeddedImageValidatorTests {
    private let context = documentContext()

    @Test func acceptedFormatsAreRecognizedBySignatureAndCarryTheirDimensions() throws {
        let png = try #require(try EmbeddedImageValidator.validate(TestImages.png(30, 20), role: .page, context: context))
        #expect(png.pixelWidth == 30 && png.pixelHeight == 20 && png.role == .page)
        let jpeg = try #require(try EmbeddedImageValidator.validate(TestImages.jpeg(16, 24), role: .cover, context: context))
        #expect(jpeg.pixelWidth == 16 && jpeg.pixelHeight == 24)
        let gif = try #require(try EmbeddedImageValidator.validate(TestImages.gif(10, 5), role: .figure, context: context))
        #expect(gif.pixelWidth == 10 && gif.pixelHeight == 5)
        #expect(EmbeddedImageValidator.sniff(TestImages.png()) == .png)
        #expect(EmbeddedImageValidator.sniff(TestImages.jpeg()) == .jpeg)
        #expect(EmbeddedImageValidator.sniff(TestImages.gif()) == .gif)
    }

    @Test func exifQuarterTurnsSwapTheDisplayedDimensions() throws {
        let rotated = try #require(try EmbeddedImageValidator.validate(TestImages.jpeg(16, 24, orientation: 6), role: .page, context: context))
        #expect(rotated.pixelWidth == 24 && rotated.pixelHeight == 16)
        let upright = try #require(try EmbeddedImageValidator.validate(TestImages.jpeg(16, 24, orientation: 1), role: .page, context: context))
        #expect(upright.pixelWidth == 16 && upright.pixelHeight == 24)
    }

    @Test func otherSignaturesAndStructurallyInvalidImagesAreRejected() throws {
        let candidates: [Data] = [
            Data(), Data("plain text".utf8), Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8), Data("BM".utf8) + Data(count: 100),
            Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(count: 20),                  // JPEG signature, no image
            Data("RIFF".utf8) + Data(count: 4) + Data("WEBP".utf8) + Data(count: 20),
            Data(count: 4) + Data("ftypheic".utf8) + Data(count: 20),
            Data(count: 4) + Data("ftypavif".utf8) + Data(count: 20),
            Data(count: 4) + Data("ftypmp42".utf8) + Data(count: 20)           // An MP4 is not an image.
        ]
        for data in candidates { #expect(try EmbeddedImageValidator.validate(data, role: .page, context: context) == nil) }
        #expect(EmbeddedImageValidator.sniff(candidates[5]) == .webP)
        #expect(EmbeddedImageValidator.sniff(candidates[6]) == .heic)
        #expect(EmbeddedImageValidator.sniff(candidates[7]) == .avif)
        #expect(EmbeddedImageValidator.sniff(candidates[8]) == nil)
    }

    @Test func dimensionsBeyondTheSharedLimitAreRejected() throws {
        let wide = TestImages.data(type: .png, width: PreviewImage.maximumPixelDimension + 1, height: 1)
        #expect(try EmbeddedImageValidator.validate(wide, role: .page, context: context) == nil)
        let limit = TestImages.data(type: .png, width: PreviewImage.maximumPixelDimension, height: 1)
        #expect(try EmbeddedImageValidator.validate(limit, role: .page, context: context)?.pixelWidth == PreviewImage.maximumPixelDimension)
    }

    @Test func encodedSizeIsLimitedToEightMebibytes() throws {
        let oversized = Data(TestImages.png().prefix(100)) + Data(count: DocumentLimits.maximumEncodedImageBytes)
        #expect(try EmbeddedImageValidator.validate(oversized, role: .page, context: context) == nil)
        #expect(DocumentLimits.maximumEncodedImageBytes == 8 * 1_048_576)
        #expect(DocumentLimits.maximumImageCount == 500)
    }

    @Test func suffixes() {
        for name in ["a.jpg", "a.JPEG", "a.png", "a.gif", "a.webp", "a.heic", "a.heif", "a.avif", "dir/a.Png"] {
            #expect(EmbeddedImageValidator.hasImageSuffix(name), "\(name)")
        }
        for name in ["a.svg", "a.bmp", "a.tiff", "a.txt", "png", "a.pdf"] { #expect(!EmbeddedImageValidator.hasImageSuffix(name), "\(name)") }
    }

    @Test func validationHonorsCancellation() async {
        let png = TestImages.png()
        let task = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try EmbeddedImageValidator.validate(png, role: .page, context: documentContext()); return false } catch is CancellationError { return true } catch { return false }
        }
        #expect(await task.value)
    }
}

private func notebook(outputs: [[String: Any]], extraCells: [[String: Any]] = []) throws -> String {
    let cell: [String: Any] = ["cell_type": "code", "metadata": [String: Any](), "execution_count": 1,
                               "source": "plot()", "outputs": outputs]
    let object: [String: Any] = ["nbformat": 4, "nbformat_minor": 5, "metadata": [String: Any](), "cells": [cell] + extraCells]
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self)
}

private func display(_ mime: String, _ payload: Any, type: String = "display_data") -> [String: Any] {
    ["output_type": type, "metadata": [String: Any](), "data": [mime: payload, "text/plain": "<Figure>"]]
}

private func parseNotebook(_ text: String, budget: PreviewBudget = PreviewBudget(maxMilliseconds: 30_000)) throws -> ParsedTextDocument {
    try JupyterNotebookAdapter().parse(DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count), context: documentContext(budget))
}

@Suite("Notebook figures")
struct NotebookFigureTests {
    @Test func pngAndJpegOutputsBecomeFigureImagesInReadingOrder() throws {
        let png = TestImages.png(30, 20)
        let jpeg = TestImages.jpeg(16, 24)
        let source = try notebook(outputs: [display("image/png", png.base64EncodedString()),
                                            display("image/jpeg", jpeg.base64EncodedString(), type: "execute_result")])
        let document = try parseNotebook(source)
        #expect(document.images.map(\.role) == [.figure, .figure])
        #expect(document.images.map(\.pixelWidth) == [30, 16])
        #expect(document.images[0].data == png)
        // Only the exact image value tokens change; source spelling and surrounding JSON stay exact.
        let expected = source.replacingOccurrences(of: "\"\(png.base64EncodedString())\"", with: "null")
            .replacingOccurrences(of: "\"\(jpeg.base64EncodedString())\"", with: "null")
        #expect(document.text.utf8.elementsEqual(expected.utf8))
        #expect(document.origin == .converted)
        #expect(document.syntax == .json)
    }

    @Test func multilineBase64ArraysDecodeLikeASingleString() throws {
        let png = TestImages.png(12, 12)
        let encoded = png.base64EncodedString(options: .lineLength64Characters)
        let lines = encoded.components(separatedBy: "\r\n").map { $0 + "\n" }
        let document = try parseNotebook(try notebook(outputs: [display("image/png", lines)]))
        #expect(document.images.count == 1)
        #expect(document.images[0].data == png)
    }

    @Test func otherRichOutputsAndInvalidPayloadsAreIgnoredWithoutFailingTheNotebook() throws {
        let source = try notebook(outputs: [
            display("image/svg+xml", "<svg/>"), display("image/gif", TestImages.gif().base64EncodedString()),
            display("text/html", "<script>alert(1)</script>"), display("image/png", "!!!not base64!!!"),
            display("image/png", Data("not an image".utf8).base64EncodedString()), display("image/png", 42),
            ["output_type": "stream", "name": "stdout", "text": ["hello\n"]]
        ])
        let document = try parseNotebook(source)
        #expect(document.images.isEmpty)
        #expect(document.origin == .converted)
        #expect(!document.text.contains("<svg/>"))
        #expect(!document.text.contains("!!!not base64!!!"))
        #expect(document.text.contains("<script>alert(1)</script>"))
        #expect(document.text.contains("hello\\n"))
    }

    @Test func atMostFiveHundredFiguresAreExtracted() throws {
        let payload = TestImages.png(8, 8).base64EncodedString()
        let outputs = (0..<501).map { _ in display("image/png", payload) }
        let document = try parseNotebook(try notebook(outputs: outputs), budget: PreviewBudget(maxInputBytes: 16_777_216, maxJSONNodes: 100_000, maxMilliseconds: 30_000))
        #expect(document.images.count == 500)
    }

    @Test func figuresDoNotChangeTheNotebooksPrivacyRanges() throws {
        let secret = ["output_type": "stream", "name": "stdout", "text": ["password = synthetic-secret-value\n"]] as [String: Any]
        let withFigure = try parseNotebook(try notebook(outputs: [display("image/png", TestImages.png().base64EncodedString()), secret]))
        let without = try parseNotebook(try notebook(outputs: [secret]))
        #expect(withFigure.sensitiveRanges.count == without.sensitiveRanges.count)
        #expect(withFigure.images.count == 1)
        #expect(without.images.isEmpty)
    }

    @Test func notebooksWithoutOutputsOrImagesHaveNoFigures() throws {
        let source = #"{"nbformat":4,"cells":[{"cell_type":"markdown","source":"text"},{"cell_type":"code","source":[]}]}"#
        #expect(try parseNotebook(source).images.isEmpty)
    }
}
