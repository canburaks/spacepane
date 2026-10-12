import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Notebook image provenance notices")
struct NotebookPresentationNoticesTests {
    private let locale = Locale(identifier: "en_US_POSIX")

    private func presentation(format: FormatID = .jupyterNotebook, origin: TextOrigin = .converted,
                              images: [PreviewImage] = []) -> TextPresentation {
        TextPresentation(formatID: format, text: #"{"image/png":null}"#, lineCount: 1, byteCount: 100,
                         encoding: .utf8, redactionCount: 0, syntax: .json, images: images, origin: origin)
    }

    @Test func omittedImageWithNoValidatedFigureMakesNoPagesPromise() {
        let notices = NotebookPresentationNotices.notices(for: presentation(), locale: locale)
        #expect(notices == [PresentationNotice(kind: .provenance, text: PreviewStrings.text(.notebookImageOutputsOmitted))])
    }

    @Test func validatedFigureAddsSeparatePagesProvenance() {
        let figure = PreviewImage(data: Data([1]), pixelWidth: 8, pixelHeight: 8, role: .figure)
        let notices = NotebookPresentationNotices.notices(for: presentation(images: [figure]), locale: locale)
        #expect(notices == [
            PresentationNotice(kind: .provenance, text: PreviewStrings.text(.notebookImageOutputsOmitted)),
            PresentationNotice(kind: .provenance, text: PreviewStrings.text(.notebookFiguresInPages))
        ])
    }

    @Test func exactNotebookAndOtherFormatsHaveNoImageOmissionNotice() {
        #expect(NotebookPresentationNotices.notices(for: presentation(origin: .source), locale: locale).isEmpty)
        #expect(NotebookPresentationNotices.notices(for: presentation(format: .json), locale: locale).isEmpty)
    }

    @Test func nonFigureAndInvalidImagesMakeNoPagesPromise() {
        let cover = PreviewImage(data: Data([1]), pixelWidth: 8, pixelHeight: 8, role: .cover)
        let invalid = PreviewImage(data: Data(), pixelWidth: 8, pixelHeight: 8, role: .figure)
        #expect(NotebookPresentationNotices.notices(for: presentation(images: [cover, invalid]), locale: locale).count == 1)
    }
}
