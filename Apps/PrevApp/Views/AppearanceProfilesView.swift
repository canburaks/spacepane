import SwiftUI
import UniformTypeIdentifiers
import PreviewContracts
import PreviewPreferences
import PreviewRenderers

struct AppearanceProfilesView: View {
    let settings: CompanionSettings
    @CompanionState private var name = ""
    @CompanionState private var isImporting = false
    @CompanionState private var isExporting = false
    @CompanionState private var transfer = AppearanceThemeTransfer()
    @CompanionState private var exportDocument: AppearanceThemeDocument?
    @Environment(\.locale) private var locale

    var body: some View {
        SettingsSection(PreviewStrings.text(.appearanceProfiles), detail: detail) {
            SettingsCard {
                HStack(alignment: .center, spacing: 12) {
                    TextField(text: $name, prompt: Text(PreviewStrings.text(.profileName))) {
                        Text(PreviewStrings.text(.profileName))
                    }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveProfile)
                    // A dimmed Save says why: in the tooltip and VoiceOver hint always, and under the field
                    // when the typed name is the problem.
                    Button(PreviewStrings.text(.saveProfile), action: saveProfile)
                        .disabled(!nameCheck.canSave)
                        .help(saveHint)
                        .accessibilityHint(Text(saveHint))
                }
                .padding(.vertical, CompanionMetrics.rowVerticalPadding)
                if let key = typedProblemKey { caption(key) }
                if settings.snapshot.appearanceProfiles.count >= PreviewAppearanceProfile.maximumCount {
                    caption(.profilesLimit)
                }
                ForEach(settings.snapshot.appearanceProfiles) { profile in
                    HStack(alignment: .firstTextBaseline, spacing: 12) { profileButtons(profile) }
                        .padding(.vertical, 8)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { transferButtons; transferProgress; Spacer(minLength: 0) }
                    VStack(alignment: .leading, spacing: 8) { transferButtons; transferProgress }
                }
                .buttonStyle(.link)
                .disabled(transfer.isReading)
                .padding(.vertical, CompanionMetrics.rowVerticalPadding)
                VStack(alignment: .leading, spacing: 6) {
                    captionText(.profilesHint)
                    captionText(.themeImportHint)
                }
                .padding(.vertical, 8)
                if let message = transfer.message {
                    transferNotice(messageKey(message), isProblem: message.isProblem)
                }
                if transfer.wasSuperseded {
                    transferNotice(.themeNotApplied, isProblem: true)
                }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], allowsMultipleSelection: false,
                      onCompletion: { result in
            transfer.importCompleted(result.flatMap { urls in
                guard urls.count == 1, let url = urls.first else { return .failure(AppearanceThemeError.invalidDocument) }
                return .success(url)
            }, settings: settings)
        }, onCancellation: { transfer.clearMessage() })
        .fileExporter(isPresented: $isExporting, document: exportDocument, contentTypes: [.json],
                      defaultFilename: PreviewStrings.text(.themeExportFilename), onCompletion: { result in
            transfer.exportCompleted(result)
            exportDocument = nil
        }, onCancellation: {
            transfer.clearMessage()
            exportDocument = nil
        })
        // A status that only changes on screen is not spoken, so the result of an export, a refused import and an
        // import that was not applied are announced. A finished import is announced by the Undo row.
        .onChange(of: transfer.message) { announceTransferResult() }
        .onChange(of: transfer.wasSuperseded) {
            if transfer.wasSuperseded { CompanionAnnouncer.announce(PreviewStrings.text(.themeNotApplied)) }
        }
        .onDisappear { transfer.cancelImport() }
    }

    private var detail: String {
        let count = settings.snapshot.appearanceProfiles.count
        return count == 0
            ? PreviewStrings.text(.profilesEmpty)
            : PreviewStrings.format(.profileCount, arguments: [count], locale: locale)
    }

    private func captionText(_ key: PreviewStrings.Key) -> some View {
        Text(PreviewStrings.text(key))
            .font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func caption(_ key: PreviewStrings.Key) -> some View {
        captionText(key).padding(.vertical, 8)
    }

    /// A failed transfer is drawn like every other problem in the companion: a caution symbol and primary text.
    /// A finished export is a quiet note.
    @ViewBuilder private func transferNotice(_ key: PreviewStrings.Key, isProblem: Bool) -> some View {
        if isProblem {
            HStack(alignment: .center, spacing: 10) {
                SettingsIconBadge(image: CompanionSymbol.warning.image, tone: .caution, size: 22)
                Text(PreviewStrings.text(key)).fixedSize(horizontal: false, vertical: true)
            }
            .font(CompanionTypography.note)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(CompanionTone.caution.color.opacity(0.28), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
        } else {
            captionText(key)
                .accessibilityAddTraits(.updatesFrequently)
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder private var transferProgress: some View {
        if transfer.isReading {
            ProgressView().controlSize(.small).accessibilityLabel(Text(PreviewStrings.text(.themeReading)))
        }
    }

    @ViewBuilder private func profileButtons(_ profile: PreviewAppearanceProfile) -> some View {
        // The profile whose appearance is the one in use is marked, in words as well as position.
        let isCurrent = profile.appearance == settings.snapshot.appearance
        Button { settings.applyAppearanceProfile(id: profile.id) } label: {
            Text(verbatim: profile.name)
                .fontWeight(isCurrent ? .semibold : .regular)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.link)
        .help(PreviewStrings.text(.applyProfile))
        .accessibilityHint(Text(PreviewStrings.text(.applyProfile)))
        .accessibilityValue(Text(verbatim: isCurrent ? PreviewStrings.text(.profileCurrent) : ""))
        if isCurrent {
            StatusPill(text: PreviewStrings.text(.profileCurrent), tone: .informational)
                .accessibilityHidden(true)
        }
        Button(PreviewStrings.text(.deleteProfile)) { settings.deleteAppearanceProfile(id: profile.id) }
            .buttonStyle(.link)
            .help(PreviewStrings.format(.deleteProfileNamed, arguments: [profile.name], locale: locale))
            .accessibilityLabel(Text(PreviewStrings.format(.deleteProfileNamed,
                arguments: [profile.name], locale: locale)))
    }

    @ViewBuilder private var transferButtons: some View {
        Button(PreviewStrings.text(.themeImport)) { transfer.clearMessage(); isImporting = true }
            .help(PreviewStrings.text(.themeImportHint))
        Button(PreviewStrings.text(.themeExport)) {
            if let data = transfer.prepareExport(settings.snapshot.appearance) {
                exportDocument = AppearanceThemeDocument(data: data)
                isExporting = true
            }
        }
        .help(PreviewStrings.text(.themeExport))
    }

    /// What Save may do with the text in the field. The name is trimmed, so a space at either end is harmless.
    private var nameCheck: ProfileNameCheck {
        ProfileNameCheck(name, existingNames: settings.snapshot.appearanceProfiles.map(\.name))
    }

    /// The reason Save is dimmed; empty while Save is available.
    private var saveHint: String {
        nameCheck.explanationKey.map { PreviewStrings.text($0) } ?? ""
    }

    /// A reason shown under the field only when the typed name is the problem. An empty field is explained by
    /// its placeholder and the tooltip, and a full list by its own sentence.
    private var typedProblemKey: PreviewStrings.Key? {
        guard let problem = nameCheck.problem else { return nil }
        switch problem {
        case .duplicate, .invalid: return nameCheck.explanationKey
        case .empty, .limitReached: return nil
        }
    }

    private func saveProfile() {
        let check = nameCheck
        guard check.canSave else { return }
        settings.saveAppearanceProfile(name: check.name)
        name = ""
    }

    private func announceTransferResult() {
        guard let message = transfer.message, message != .imported else { return }
        CompanionAnnouncer.announce(PreviewStrings.text(messageKey(message)))
    }

    private func messageKey(_ message: AppearanceThemeTransfer.Message) -> PreviewStrings.Key {
        switch message {
        case .imported: .themeImported
        case .exported: .themeExported
        case .failed: .themeTransferFailed
        case .importError(let error):
            switch error {
            case .tooLarge: .themeTooLarge
            case .invalidDocument: .themeInvalid
            case .unsupportedVersion: .themeUnsupportedVersion
            case .cannotRead: .themeCannotRead
            }
        }
    }
}

/// Only used by the system save sheet; no document scene or auxiliary app window is created.
private struct AppearanceThemeDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw AppearanceThemeError.invalidDocument }
        _ = try AppearanceThemeCodec.decode(data)
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
