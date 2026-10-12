import Testing
@testable import PreviewRenderers

@Suite("Q53 shared command capabilities")
struct Q53CommandAvailabilityTests {
    @Test func sourceTextHasTheCurrentCopySearchLineAndZoomCapabilities() {
        let availability = capabilities(selectionCopy: true, wholeTextCopy: true, search: .full,
            sourceLineNavigation: true, zoom: true)
        #expect(availability.commands == [.copy, .copyConcealed, .find, .findNext, .findPrevious,
            .goToLine, .zoomIn, .zoomOut, .actualSize])
    }

    @Test func renderedTextAndTablesNeverBorrowSourceLineNavigationOrUnsupportedSearch() {
        let rendered = capabilities(selectionCopy: true, wholeTextCopy: true, search: .full, zoom: true)
        #expect(!rendered.contains(.goToLine) && rendered.contains(.findNext))
        let table = capabilities(selectionCopy: true, wholeTextCopy: true, search: .filter, zoom: true)
        #expect(table.contains(.find) && !table.contains(.findNext) && !table.contains(.findPrevious))
        #expect(!table.contains(.goToLine))
    }

    @Test func picturesAndSearchUnavailableViewsDoNotAdvertiseSearchOrTextZoom() {
        let pictures = capabilities(wholeTextCopy: true)
        #expect(pictures.commands == [.copyConcealed])
        let contents = capabilities(selectionCopy: true, wholeTextCopy: true, zoom: true)
        #expect(contents.contains(.copy) && contents.contains(.zoomIn))
        #expect(!contents.contains(.find) && !contents.contains(.findNext) && !contents.contains(.findPrevious))
    }

    @Test func geometryUsesOnlyTheExistingViewportCommandTableAndNeedsAnOperableViewport() {
        let geometry = capabilities(geometryNavigation: true)
        #expect(geometry.commands == [.fitModel, .resetView, .viewFront, .viewSide, .viewTop,
            .cameraZoomIn, .cameraZoomOut])
        #expect(!geometry.contains(.copyConcealed) && !geometry.contains(.goToLine))
        #expect(capabilities().commands.isEmpty, "A failed or absent viewport supplies no navigation capability")
    }

    @Test func modeChordsAreOnlyTheExistingDisplayedPositionsAndNeverPastNine() {
        #expect(capabilities(modeCount: 1).commands.isEmpty)
        #expect(capabilities(modeCount: 3).commands == [.mode(1), .mode(2), .mode(3)])
        let many = capabilities(modeCount: 100)
        #expect(many.commands == (1...9).map { PreviewCommand.mode($0) })
        #expect(!many.contains(.mode(0)) && !many.contains(.mode(10)))
    }

    @Test func noContentSuppressesEvenInconsistentSuppliedCapabilities() {
        let empty = PreviewCommandAvailability(hasContent: false, selectionCopy: true, wholeTextCopy: true,
            search: .full, sourceLineNavigation: true, zoom: true, geometryNavigation: true, modeCount: 3)
        #expect(empty.commands.isEmpty)
        for command in PreviewCommand.allCases { #expect(!empty.contains(command)) }
    }

    private func capabilities(selectionCopy: Bool = false, wholeTextCopy: Bool = false,
                              search: PreviewCommandAvailability.Search = .none,
                              sourceLineNavigation: Bool = false, zoom: Bool = false,
                              geometryNavigation: Bool = false, modeCount: Int = 1) -> PreviewCommandAvailability {
        .init(hasContent: true, selectionCopy: selectionCopy, wholeTextCopy: wholeTextCopy, search: search,
            sourceLineNavigation: sourceLineNavigation, zoom: zoom, geometryNavigation: geometryNavigation,
            modeCount: modeCount)
    }
}
