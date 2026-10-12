import PreviewContracts

public struct TextAdapter: FormatAdapter, TextInputPolicyProviding {
    public init() {}
    /// Plain text is line oriented, so a file over the input budget shows its leading complete lines.
    public var textInputPolicy: TextInputPolicy { .leadingRecords(.line) }
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        return ParsedTextDocument(text: input.text)
    }
}

public enum StandardFormatAdapters {
    public static let registrations: [AdapterRegistration] = [
        AdapterRegistration(formatID: .plainText) { TextAdapter() },
        AdapterRegistration(formatID: .extensionlessText, binaryAdapter: { ExtensionlessTextAdapter() }),
        AdapterRegistration(formatID: .json) { JSONSourceAdapter() },
        AdapterRegistration(formatID: .jsonLines) { JSONLinesAdapter(allowsMalformedRecords: true) },
        AdapterRegistration(formatID: .sourceCode) { SourceCodeAdapter() },
        AdapterRegistration(formatID: .yaml) { YAMLSourceAdapter() },
        AdapterRegistration(formatID: .toml) { TOMLSourceAdapter() },
        AdapterRegistration(formatID: .environment) { EnvironmentSourceAdapter() },
        AdapterRegistration(formatID: .packageJSON) { JSONSourceAdapter() },
        AdapterRegistration(formatID: .markdown) { MarkdownSourceAdapter() },
        AdapterRegistration(formatID: .diff) { DiffSourceAdapter() },
        AdapterRegistration(formatID: .xml) { XMLSourceAdapter() },
        AdapterRegistration(formatID: .propertyList, emptyInputPolicy: .emptyPreview, binaryAdapter: { PropertyListSourceAdapter() }),
        AdapterRegistration(formatID: .strings) { StringsSourceAdapter() },
        AdapterRegistration(formatID: .stringsDictionary, emptyInputPolicy: .emptyPreview, binaryAdapter: { PropertyListSourceAdapter() }),
        AdapterRegistration(formatID: .opml) { XMLSourceAdapter() },
        AdapterRegistration(formatID: .csv) { DelimitedTextAdapter(dialect: .comma) },
        AdapterRegistration(formatID: .tsv) { DelimitedTextAdapter(dialect: .tab) },
        AdapterRegistration(formatID: .subRip) { SubtitleAdapter(variant: .subRip) },
        AdapterRegistration(formatID: .webVTT) { SubtitleAdapter(variant: .webVTT) },
        AdapterRegistration(formatID: .nfo, binaryAdapter: { TextArtAdapter() }),
        AdapterRegistration(formatID: .jupyterNotebook, defaultBudget: JupyterNotebookAdapter.defaultBudget,
                            emptyInputPolicy: .emptyPreview, binaryAdapter: { JupyterNotebookAdapter() })
    ] + ContainerFormatAdapters.registrations
        // Each workstream appends its own `<Family>FormatAdapters.registrations` on one line
        // directly below its marker, keeping families independent of each other.
        // [archives]
        + ArchiveFormatAdapters.registrations
        // [markup]
        + MarkupFormatAdapters.registrations
        // [diagrams]
        + DiagramFormatAdapters.registrations
        // [packages]
        + PackageFormatAdapters.registrations
        // [data]
        + DataFormatAdapters.registrations
        // [code]
        + CodeFormatAdapters.registrations
        // [ebooks]
        + DocumentFormatAdapters.registrations
        // [mesh]
        + MeshFormatAdapters.registrations
}
