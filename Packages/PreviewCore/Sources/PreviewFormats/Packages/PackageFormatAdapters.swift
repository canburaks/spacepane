import PreviewContracts

/// Explicit registrations for the package, certificate and disk-image inspection formats.
public enum PackageFormatAdapters {
    public static let registrations: [AdapterRegistration] = [
        AdapterRegistration(formatID: .applicationBundle, urlAdapter: { ApplicationBundleAdapter() }),
        AdapterRegistration(formatID: .iosApp, defaultBudget: .containerScan, randomAccessAdapter: { IOSApplicationAdapter() }),
        AdapterRegistration(formatID: .androidApp, defaultBudget: .containerScan, randomAccessAdapter: { AndroidPackageAdapter() }),
        AdapterRegistration(formatID: .provisioningProfile, binaryAdapter: { ProvisioningProfileAdapter() }),
        AdapterRegistration(formatID: .certificate, binaryAdapter: { CertificateAdapter() }),
        AdapterRegistration(formatID: .installerPackage, defaultBudget: .containerScan, randomAccessAdapter: { InstallerPackageAdapter() }),
        AdapterRegistration(formatID: .diskImage, defaultBudget: .containerScan, randomAccessAdapter: { DiskImageAdapter() }),
        AdapterRegistration(formatID: .torrent, binaryAdapter: { TorrentAdapter() })
    ]
}
