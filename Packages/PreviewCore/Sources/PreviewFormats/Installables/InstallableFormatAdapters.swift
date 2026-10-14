import PreviewContracts

/// Explicit registrations for the installable-package formats of decision 030. npm tarballs and Python
/// source distributions are not here: they stay gzip archives, and `TARListingAdapter` adds their
/// install-time findings to the listing.
public enum InstallableFormatAdapters {
    public static let registrations: [AdapterRegistration] = [
        AdapterRegistration(formatID: .pythonWheel, defaultBudget: .containerScan, randomAccessAdapter: { PythonWheelAdapter() })
    ]
}
