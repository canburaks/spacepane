import PreviewContracts

/// Counts effective choices for the whole catalog or one group. The same value
/// drives the sidebar status, the page header and each group's mixed state.
struct FileTypeEnablementSummary: Equatable {
    enum State: Equatable { case all, some, none }

    let enabled: Int
    let total: Int

    init(_ descriptors: [FormatDescriptor], isEnabled: (FormatID) -> Bool) {
        total = descriptors.count
        enabled = descriptors.reduce(0) { $0 + (isEnabled($1.id) ? 1 : 0) }
    }

    var state: State {
        if enabled == 0 { return .none }
        return enabled == total ? .all : .some
    }
}
