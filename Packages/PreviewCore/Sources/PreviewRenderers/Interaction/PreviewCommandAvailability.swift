/// Capabilities of the actual displayed surface, supplied once by the facade. This does not derive models,
/// inspect selected values, or dispatch a command; help and the existing dispatch path share this boundary.
struct PreviewCommandAvailability: Sendable {
    enum Search: Equatable, Sendable { case none, filter, full }
    let hasContent: Bool
    let selectionCopy: Bool
    let wholeTextCopy: Bool
    let search: Search
    let sourceLineNavigation: Bool
    let zoom: Bool
    let geometryNavigation: Bool
    let modeCount: Int

    func contains(_ command: PreviewCommand) -> Bool {
        guard hasContent else { return false }
        switch command {
        case .copy: return selectionCopy
        case .copyConcealed: return wholeTextCopy
        case .find: return search != .none
        case .findNext, .findPrevious: return search == .full
        case .goToLine: return sourceLineNavigation
        case .zoomIn, .zoomOut, .actualSize: return zoom
        case .mode(let number):
            return modeCount > 1 && PreviewCommand.modeNumbers.contains(number) && number <= modeCount
        case .fitModel, .resetView, .viewFront, .viewSide, .viewTop, .cameraZoomIn, .cameraZoomOut:
            return geometryNavigation
        }
    }

    var commands: [PreviewCommand] { PreviewCommand.allCases.filter(contains) }
}
