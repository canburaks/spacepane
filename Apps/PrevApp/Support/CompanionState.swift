import SwiftUI

// Select the established macOS 15-compatible property wrapper explicitly. SDK 27 also
// exports an @State macro, whose SwiftUIMacros plugin is absent from Command Line Tools.
// This alias is the original SwiftUI.State, with its normal ownership and observation.
typealias CompanionState<Value> = SwiftUI.State<Value>
