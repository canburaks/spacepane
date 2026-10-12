import SwiftUI

/// System symbol names used by the shell and shared components. Feature views
/// keep their own symbols next to the view that gives them meaning.
enum CompanionSymbol: String {
    case general = "slider.horizontal.3"
    case fileTypes = "doc.badge.gearshape"
    case theme = "paintbrush"
    case about = "info.circle"
    case tryPreview = "doc.text.magnifyingglass"
    case warning = "exclamationmark.triangle"
    /// A neutral note that states a fact and asks for nothing.
    case info = "info.circle.fill"

    var image: Image { Image(systemName: rawValue) }
}
