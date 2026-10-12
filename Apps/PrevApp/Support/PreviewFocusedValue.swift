import SwiftUI

private struct PreviewSessionKey: FocusedValueKey { typealias Value = PreviewSession }
extension FocusedValues {
    var previewSession: PreviewSession? {
        get { self[PreviewSessionKey.self] }
        set { self[PreviewSessionKey.self] = newValue }
    }
}
