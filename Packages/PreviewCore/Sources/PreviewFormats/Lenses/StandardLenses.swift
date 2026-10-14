import PreviewContracts

/// Which lenses read which formats (decision 029). The one place to attach a lens to a format: a new lens
/// adds a row here and needs no change to the pipeline, the hosts or any adapter.
public enum StandardLenses {
    static let table: [FormatID: [any PreviewTextLens]] = [
        .sourceCode: [ScriptEffectsLens()],
        .extensionlessText: [ScriptEffectsLens()],
        .json: [AutoRunConfigLens(), CredentialExportLens()],
        .jsonWithComments: [AutoRunConfigLens()],
        .packageJSON: [AutoRunConfigLens()],
        .csv: [CredentialExportLens()],
        .tsv: [CredentialExportLens()],
        .propertyList: [LaunchdJobLens()],
        // Decision 030: a `.pth` path file is shown as text; the lens never runs on the pickle summaries.
        .pickle: [PythonPathFileLens()],
    ]

    /// Registrations with their lenses attached; formats without a row are returned unchanged.
    public static func attach(to registrations: [AdapterRegistration]) -> [AdapterRegistration] {
        registrations.map { registration in
            guard let lenses = table[registration.formatID] else { return registration }
            return registration.adding(lenses: lenses)
        }
    }
}
