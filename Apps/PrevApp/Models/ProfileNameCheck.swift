import Foundation
import PreviewContracts
import PreviewRenderers

/// Whether the text in the profile name field can be saved and, when it cannot, why. The text is trimmed
/// first, so a space at either end never disables Save without a word of explanation.
struct ProfileNameCheck: Equatable, Sendable {
    enum Problem: Equatable, Sendable {
        /// Nothing, or only white space, was typed.
        case empty
        /// Too long, or it holds a line break, a control character or a direction mark.
        case invalid
        /// A saved profile already has this name.
        case duplicate
        /// The most profiles the app keeps are already saved.
        case limitReached
    }

    /// The trimmed name Save would store.
    let name: String
    let problem: Problem?

    var canSave: Bool { problem == nil }

    init(_ text: String, existingNames: [String]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        name = trimmed
        if existingNames.count >= PreviewAppearanceProfile.maximumCount {
            problem = .limitReached
        } else if trimmed.isEmpty {
            problem = .empty
        } else if !PreviewAppearanceProfile.isValidName(trimmed) {
            problem = .invalid
        } else if existingNames.contains(trimmed) {
            problem = .duplicate
        } else {
            problem = nil
        }
    }

    /// The sentence that explains a disabled Save, or nil when Save is available.
    var explanationKey: PreviewStrings.Key? {
        guard let problem else { return nil }
        switch problem {
        case .empty: return .profileSaveEmpty
        case .invalid: return .profileSaveInvalid
        case .duplicate: return .profileSaveDuplicate
        case .limitReached: return .profilesLimit
        }
    }
}
