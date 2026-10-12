import PreviewContracts

/// Registrations for the code, configuration and caption formats. The shared list appends
/// `CodeFormatAdapters.registrations` below its `[code]` marker.
public enum CodeFormatAdapters {
    public static let registrations: [AdapterRegistration] = [
        AdapterRegistration(formatID: .iniConfiguration) { INIConfigurationAdapter() },
        AdapterRegistration(formatID: .log) { LogAdapter() },
        AdapterRegistration(formatID: .jsonWithComments) { JSONCAdapter() },
        AdapterRegistration(formatID: .subStationAlpha) { CaptionAdapter(dialect: .subStationAlpha) },
        AdapterRegistration(formatID: .timedText) { CaptionAdapter(dialect: .timedText) },
        AdapterRegistration(formatID: .subViewer) { CaptionAdapter(dialect: .subViewer) },
        AdapterRegistration(formatID: .lyrics) { CaptionAdapter(dialect: .lyrics) },
        AdapterRegistration(formatID: .microDVD, binaryAdapter: { MicroDVDAdapter() })
    ]
}

/// CSV and TSV opt into leading-prefix reads here, so the tabular adapter file and the shared
/// registration list stay unchanged. CSV records may contain quoted line breaks, so its cut must
/// fall outside a quoted field; TSV has no quoting.
extension DelimitedTextAdapter: TextInputPolicyProviding {
    public var textInputPolicy: TextInputPolicy {
        .leadingRecords(dialect == .comma ? .quotedRecord : .line)
    }
}
