/// How the settings status is drawn. The words come from `SettingsStatus`; this only picks the tone. Nothing
/// is ever drawn as confirmed: the app cannot know that the extensions are on or that Finder uses this
/// provider, so a healthy status is neutral and only a verified problem is a caution.
extension SettingsStatus.Tone {
    var companionTone: CompanionTone {
        switch self {
        case .neutral: return .neutral
        case .caution: return .caution
        }
    }
}
