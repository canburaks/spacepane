import Foundation

/// Stable identities for the package, certificate and disk-image inspection formats. The raw values
/// are persisted file-type preference keys; never derive them from a display name.
public extension FormatID {
    /// macOS application bundles (`.app` directories).
    static let applicationBundle = FormatID(rawValue: "package.application")
    /// iOS/iPadOS application archives (`.ipa`).
    static let iosApp = FormatID(rawValue: "package.ios-app")
    /// Android application packages (`.apk`).
    static let androidApp = FormatID(rawValue: "package.android")
    /// Apple provisioning profiles (`.mobileprovision`, `.provisionprofile`).
    static let provisioningProfile = FormatID(rawValue: "config.provisioning-profile")
    /// X.509 certificates in DER or PEM form, and PEM files that carry private keys (never shown).
    static let certificate = FormatID(rawValue: "security.certificate")
    /// Flat installer packages (`.pkg`, XAR containers).
    static let installerPackage = FormatID(rawValue: "package.installer")
    /// UDIF disk images (`.dmg`).
    static let diskImage = FormatID(rawValue: "disk.image")
    /// BitTorrent metainfo files (`.torrent`).
    static let torrent = FormatID(rawValue: "data.torrent")
}
