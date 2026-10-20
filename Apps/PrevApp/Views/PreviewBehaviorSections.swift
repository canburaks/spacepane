import SwiftUI
import PreviewContracts
import PreviewRenderers

/// Choices that shape every preview and thumbnail and are shared with both extensions: live reload and
/// whether thumbnails may show a concealed excerpt. The companion is the writer; hosts read new values
/// for new requests, and an open preview or a cached thumbnail may keep showing earlier content.
struct PreviewBehaviorSection: View {
    let settings: CompanionSettings

    var body: some View {
        SettingsSection(PreviewStrings.text(.behaviorPreviewsTitle)) {
            SettingsCard {
                SettingsToggleRow(PreviewStrings.text(.behaviorReloadTitle),
                                  subtitle: PreviewStrings.text(.behaviorReloadSubtitle),
                                  isOn: Binding(get: { settings.snapshot.reloadsOnFileChange },
                                                set: { settings.setReloadsOnFileChange($0) }))
                SettingsToggleRow(PreviewStrings.text(.behaviorThumbnailsTitle),
                                  subtitle: PreviewStrings.text(.behaviorThumbnailsSubtitle),
                                  isOn: Binding(get: { settings.snapshot.showsContentThumbnails },
                                                set: { settings.setShowsContentThumbnails($0) }))
            }
        }
        .disabled(settings.isLoading)
    }
}

/// How deep a folder preview lists and whether it lists hidden items. The values travel to the
/// folder adapter only through the request options derived from the shared snapshot.
struct FolderPreviewSection: View {
    let settings: CompanionSettings
    @Environment(\.locale) private var locale

    var body: some View {
        let depth = settings.snapshot.folderDepth
        let foldersEnabled = settings.isEnabled(.folder)
        let title = PreviewStrings.text(.behaviorFolderDepthTitle)
        SettingsSection(PreviewStrings.text(.behaviorFoldersTitle)) {
            SettingsCard {
                SettingsToggleRow(PreviewStrings.text(.generalFoldersTitle),
                                  subtitle: PreviewStrings.text(.generalFoldersSubtitle),
                                  isOn: Binding(get: { settings.isEnabled(.folder) },
                                                set: { settings.setEnabled($0, for: .folder) }))
                SettingsRow(title, subtitle: PreviewStrings.text(.behaviorFolderDepthSubtitle)) {
                    HStack(spacing: 8) {
                        Text(PreviewStrings.format(.behaviorFolderDepthValue, arguments: [depth], locale: locale))
                            .monospacedDigit()
                            .foregroundStyle(CompanionInk.hint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .accessibilityHidden(true)
                        Stepper(value: Binding(get: { settings.snapshot.folderDepth },
                                               set: { settings.setFolderDepth($0) }),
                                in: PreviewRequestOptions.folderDepthRange) {
                            Text(title)
                        }
                        .labelsHidden()
                        .help(title)
                        .accessibilityLabel(Text(title))
                        .accessibilityValue(Text(depth, format: .number.locale(locale)))
                        .accessibilityHint(Text(PreviewStrings.text(.behaviorFolderDepthSubtitle)))
                    }
                }
                .disabled(!foldersEnabled)
                SettingsToggleRow(PreviewStrings.text(.behaviorHiddenTitle),
                                  subtitle: PreviewStrings.text(.behaviorHiddenSubtitle),
                                  isOn: Binding(get: { settings.snapshot.showsHiddenFolderItems },
                                                set: { settings.setShowsHiddenFolderItems($0) }))
                    .disabled(!foldersEnabled)
            }
        }
        .disabled(settings.isLoading)
    }
}
