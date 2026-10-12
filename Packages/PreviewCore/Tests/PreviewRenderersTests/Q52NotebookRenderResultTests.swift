import Foundation
import Testing
@testable import PreviewRenderers

// The old API forwards through the same result-producing implementation.
@Suite("Q52 notebook render result compatibility")
struct Q52NotebookRenderResultTests {
    @Test func renderResultCarriesCountAndOldRenderReturnsTheSameDocument() throws {
        let source = #"{"nbformat":4,"cells":[{"cell_type":"markdown","source":""},{"cell_type":"markdown","source":"Q52Safe"}]}"#
        let locale = Locale(identifier: "en_US")
        let result = try #require(SafeNotebookDocument.renderResult(source, locale: locale))
        #expect(result.totalCells == 2)
        #expect(SafeNotebookDocument.render(source, locale: locale) == result.document)
        #expect(SafeNotebookDocument.renderResult("{", locale: locale) == nil)
    }
}
