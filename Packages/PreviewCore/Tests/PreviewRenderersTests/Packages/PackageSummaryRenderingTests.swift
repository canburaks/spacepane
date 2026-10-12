import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PreviewContracts
@testable import PreviewRenderers

@Suite("Package summary rendering", .serialized)
@MainActor
struct PackageSummaryRenderingTests {
    private let formats: [FormatID] = [.applicationBundle, .iosApp, .androidApp, .provisioningProfile, .certificate,
                                       .installerPackage, .diskImage, .torrent]

    private func presentation(_ source: String, format: FormatID, images: [PreviewImage] = [], redactions: Int = 0) -> TextPresentation {
        TextPresentation(formatID: format, text: source, lineCount: source.split(separator: "\n", omittingEmptySubsequences: false).count,
                         byteCount: source.utf8.count, encoding: .utf8, redactionCount: redactions, syntax: .json, images: images)
    }

    private func flatten(_ nodes: [SafeOutlineNode]) -> [SafeOutlineNode] { nodes.flatMap { [$0] + flatten($0.children) } }

    private func png(_ edge: Int) -> Data {
        let context = CGContext(data: nil, width: edge, height: edge, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: edge, height: edge))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func icon(_ edge: Int = 64) -> PreviewImage { PreviewImage(data: png(edge), pixelWidth: edge, pixelHeight: edge, role: .icon) }

    // MARK: Label schema

    @Test func everyPackageFormatBelongsToExactlyOneSchemaSetAndStartsInSummary() throws {
        for format in formats {
            let owners = SafeSchemaLabels.labelSets.filter { $0.formats.contains(format) }
            #expect(owners.count == 1, "\(format.rawValue)")
            let modes = SafePreviewModes(presentation(#"{"name":"x"}"#, format: format), locale: Locale(identifier: "en"))
            #expect(modes.summary != nil && modes.initialMode(for: format) == .summary)
            #expect(modes.available.contains(.source) && modes.available.contains(.summary))
        }
    }

    @Test func packageSummariesWithAFileListStillStartInSummaryWhileArchivesAndFoldersOpenInFiles() throws {
        // The shape the ipa, apk, pkg and torrent adapters write (`PackageSummaryFields.listing`): decision 017
        // keeps Summary first for them even though Files and Tree can be built from the same entries.
        let listing = #"{"archiveFormat":"ZIP","listedEntries":2,"partial":false,"entries":[{"path":"Payload/App.app/","type":"directory"},{"path":"Payload/App.app/Info.plist","type":"file","bytes":512}]}"#
        let english = Locale(identifier: "en")
        for format in [FormatID.iosApp, .androidApp, .installerPackage, .torrent] {
            let modes = SafePreviewModes(presentation(listing, format: format), locale: english)
            #expect(modes.files != nil && modes.tree != nil, "\(format.rawValue)")
            #expect(modes.available.contains(.files) && modes.available.contains(.tree) && modes.available.contains(.summary))
            #expect(modes.initialMode(for: format) == .summary, "\(format.rawValue)")
        }
        // The same shape in an archive or a folder opens in the Files table (decision 014).
        for format in [FormatID.zip, .tar, .sevenZip, .folder] {
            let modes = SafePreviewModes(presentation(listing, format: format), locale: english)
            #expect(modes.files != nil)
            #expect(modes.initialMode(for: format) == .files, "\(format.rawValue)")
        }
    }

    @Test func aPackageListingTooLargeForTheSummaryOutlineStillOpensInFiles() throws {
        // Above 256 Ki UTF-16 units the Summary outline is unavailable while the listing still parses; Files is
        // then the useful first view, not the raw summary text.
        var entries: [String] = []
        for index in 0..<4_500 {
            entries.append("{\"path\":\"Payload/App.app/Assets/image-\(index).png\",\"type\":\"file\",\"bytes\":10}")
        }
        let source = "{\"archiveFormat\":\"ZIP\",\"listedEntries\":4500,\"partial\":false,\"entries\":[" + entries.joined(separator: ",") + "]}"
        #expect(source.utf16.count > 262_144)
        let modes = SafePreviewModes(presentation(source, format: .iosApp), locale: Locale(identifier: "en"))
        #expect(modes.summary == nil && modes.files != nil)
        #expect(modes.initialMode(for: .iosApp) == .files)
    }

    @Test func everyAllowedFieldHasALocalizedLabelKey() {
        let set = SummaryLabelSet.packages
        let parents: [[String]] = [[], ["signature"], ["provisioning"], ["entries", "[]"], ["packages", "[]"], ["partitions", "[]"], ["certificates", "[]"]]
        var checked = 0
        for parent in parents {
            for field in set.fields(parent) ?? [] {
                checked += 1
                let key = set.keys[field]
                #expect(key != nil, "No label for \(parent) \(field)")
                if let key { #expect(PreviewStrings.text(key) != key.rawValue && !PreviewStrings.text(key).isEmpty) }
            }
        }
        #expect(checked > 90)
        #expect(set.fields(["signature", "entitlements"]) == nil && set.fields(["partitions", "[]", "name"]) == nil)
        for key in set.valueLabels.flatMap({ $0.value.values }) { #expect(!PreviewStrings.text(key).isEmpty) }
    }

    @Test func applicationSummaryTranslatesFieldNamesButNeverDocumentValues() throws {
        let source = """
        {"name":"Synthetic","bundleIdentifier":"com.example.synthetic","architectures":["arm64","x86_64"],"executableKind":"universal",
         "signature":{"status":"adHoc","signingIdentifier":"com.example.synthetic","hardenedRuntime":true,"appSandbox":false,
                      "entitlements":{"name":"entitlement-named-name","com.apple.security.app-sandbox":true,"status":"entitlement-named-status"},
                      "signatureVerified":false,"notarizationChecked":false},
         "bundleSize":1234567,"bundleItems":42,"partial":false}
        """
        let modes = SafePreviewModes(presentation(source, format: .applicationBundle), locale: Locale(identifier: "de_DE"))
        let nodes = flatten(try #require(modes.summary))
        func node(_ name: String) -> SafeOutlineNode? { nodes.first { $0.name == name } }
        #expect(node(PreviewStrings.text(.packageBundleIdentifier))?.value == "com.example.synthetic")
        #expect(node(PreviewStrings.text(.packageExecutableKind))?.value == PreviewStrings.text(.packageKindUniversal))
        #expect(node(PreviewStrings.text(.packageStatus))?.value == PreviewStrings.text(.packageStatusAdHoc))
        #expect(node(PreviewStrings.text(.packageHardenedRuntime))?.value == PreviewStrings.text(.summaryBooleanTrue))
        #expect(node(PreviewStrings.text(.packageAppSandbox))?.value == PreviewStrings.text(.summaryBooleanFalse))
        #expect(node(PreviewStrings.text(.packageBundleSize))?.value == "1.234.567")
        #expect(node(PreviewStrings.text(.packageNotarizationChecked))?.value == PreviewStrings.text(.summaryBooleanFalse))
        // Architecture names are technical identifiers and entitlement keys are document content.
        #expect(nodes.contains { $0.value == "arm64" } && nodes.contains { $0.name == "com.apple.security.app-sandbox" })
        // Keys inside the entitlements object that match a schema field name are not translated.
        let entitlementNames = nodes.filter { $0.value == "entitlement-named-name" || $0.value == "entitlement-named-status" }.map(\.name)
        #expect(entitlementNames.sorted() == ["name", "status"])
    }

    @Test func listingEntriesUseTheSharedKindAndNumberFormatting() throws {
        let source = #"{"archiveFormat":"ZIP","listedEntries":1,"partial":false,"entries":[{"path":"Payload/App.app/name","type":"directory","bytes":2048,"modified":"2026-01-01T00:00:00Z"}]}"#
        let modes = SafePreviewModes(presentation(source, format: .iosApp), locale: Locale(identifier: "de_DE"))
        let nodes = flatten(try #require(modes.summary))
        #expect(nodes.first { $0.name == PreviewStrings.text(.packageContainerFormat) }?.value == "ZIP")
        #expect(nodes.first { $0.name == PreviewStrings.text(.summaryPath) }?.value == "Payload/App.app/name")
        #expect(nodes.first { $0.name == PreviewStrings.text(.summaryType) }?.value == PreviewStrings.text(.summaryKindDirectory))
        #expect(nodes.first { $0.name == PreviewStrings.text(.summaryBytes) }?.value == "2.048")
        #expect(nodes.contains { $0.name == PreviewStrings.text(.packageModified) && $0.value == "2026-01-01T00:00:00Z" })
    }

    @Test func profileCertificateAndTorrentValuesAreLabelledPerFormat() throws {
        let profile = #"{"name":"Synthetic","profileType":"enterprise","expired":true,"provisionedDevices":1500,"certificates":["Dev"],"signatureVerified":false}"#
        let profileNodes = flatten(try #require(SafePreviewModes(presentation(profile, format: .provisioningProfile), locale: Locale(identifier: "de_DE")).summary))
        #expect(profileNodes.first { $0.name == PreviewStrings.text(.packageProfileType) }?.value == PreviewStrings.text(.packageProfileEnterprise))
        #expect(profileNodes.first { $0.name == PreviewStrings.text(.packageExpired) }?.value == PreviewStrings.text(.summaryBooleanTrue))
        #expect(profileNodes.first { $0.name == PreviewStrings.text(.packageProvisionedDevices) }?.value == "1.500")
        let certificate = #"{"encoding":"PEM","certificateCount":1,"certificates":[{"subject":"CN=a","sha256":"AA:BB","publicKeyBits":2048,"expired":false}],"privateKeys":1,"privateKeyKinds":["RSA PRIVATE KEY"]}"#
        let certificateNodes = flatten(try #require(SafePreviewModes(presentation(certificate, format: .certificate), locale: Locale(identifier: "en")).summary))
        #expect(certificateNodes.contains { $0.name == PreviewStrings.text(.packagePrivateKeys) && $0.value == "1" })
        #expect(certificateNodes.contains { $0.name == PreviewStrings.text(.packageSHA256) && $0.value == "AA:BB" })
        #expect(certificateNodes.contains { $0.name == PreviewStrings.text(.packagePublicKeyBits) && $0.value == "2,048" })
        #expect(certificateNodes.contains { $0.value == "RSA PRIVATE KEY" })
        let torrent = #"{"name":"Album","layout":"multipleFiles","fileCount":3,"totalBytes":9000,"private":true,"trackers":["udp://t.example.test:6969"],"infoHash":"abc123"}"#
        let torrentNodes = flatten(try #require(SafePreviewModes(presentation(torrent, format: .torrent), locale: Locale(identifier: "fr_FR")).summary))
        #expect(torrentNodes.first { $0.name == PreviewStrings.text(.packageLayout) }?.value == PreviewStrings.text(.packageLayoutMultiple))
        #expect(torrentNodes.first { $0.name == PreviewStrings.text(.packagePrivateTorrent) }?.value == PreviewStrings.text(.summaryBooleanTrue))
        #expect(torrentNodes.contains { $0.name == PreviewStrings.text(.packageInfoHash) && $0.value == "abc123" })
    }

    @Test func installerDiskImageAndAndroidFieldsAreLabelled() throws {
        let installer = #"{"title":"T","packages":[{"identifier":"com.example.p","version":"1","installKilobytes":4096,"scripts":["preinstall"]}],"signed":true}"#
        let installerNodes = flatten(try #require(SafePreviewModes(presentation(installer, format: .installerPackage), locale: Locale(identifier: "de_DE")).summary))
        #expect(installerNodes.contains { $0.name == PreviewStrings.text(.packageInstallKilobytes) && $0.value == "4.096" })
        #expect(installerNodes.contains { $0.name == PreviewStrings.text(.packageScripts) })
        #expect(installerNodes.contains { $0.name == PreviewStrings.text(.packageStatusSigned) && $0.value == PreviewStrings.text(.summaryBooleanTrue) })
        let image = #"{"udifVersion":4,"imageBytes":1048576,"partitions":[{"name":"disk image (Apple_HFS : 0)","bytes":512}],"compressions":["zlib"],"internetEnabled":false}"#
        let imageNodes = flatten(try #require(SafePreviewModes(presentation(image, format: .diskImage), locale: Locale(identifier: "en")).summary))
        #expect(imageNodes.contains { $0.name == PreviewStrings.text(.packageImageBytes) && $0.value == "1,048,576" })
        #expect(imageNodes.contains { $0.name == PreviewStrings.text(.summaryName) && $0.value == "disk image (Apple_HFS : 0)" })
        let android = #"{"packageName":"com.example","versionCode":2147483647,"minSdkVersion":"24","permissions":["android.permission.INTERNET"],"debuggable":false}"#
        let androidNodes = flatten(try #require(SafePreviewModes(presentation(android, format: .androidApp), locale: Locale(identifier: "de_DE")).summary))
        // A version code is an identifier, not a quantity: it is never given a grouping separator.
        #expect(androidNodes.contains { $0.name == PreviewStrings.text(.packageVersionCode) && $0.value == "2147483647" })
        #expect(androidNodes.contains { $0.value == "android.permission.INTERNET" })
    }

    // MARK: Icon mode

    @Test func iconModeAppearsOnlyWhenAnIconWasExtractedAndSummaryStaysFirst() {
        let with = SafePreviewModes(presentation(#"{"name":"x"}"#, format: .iosApp, images: [icon()]), locale: Locale(identifier: "en"))
        #expect(with.available.contains(.icon) && with.initialMode(for: .iosApp) == .summary)
        #expect(with.available.first == .source)
        let without = SafePreviewModes(presentation(#"{"name":"x"}"#, format: .iosApp), locale: Locale(identifier: "en"))
        #expect(!without.available.contains(.icon))
        let page = PreviewImage(data: png(8), pixelWidth: 8, pixelHeight: 8, role: .page)
        #expect(!SafePreviewModes(presentation(#"{"name":"x"}"#, format: .iosApp, images: [page]), locale: Locale(identifier: "en")).available.contains(.icon))
        #expect(NativePreviewMode.icon.title == .previewModeIcon)
    }

    @Test func theIconViewDrawsAndClearsTheExtractedIcon() throws {
        let view = try #require(SafeModeViewRegistry.makeView(for: .icon) as? PackageIconView)
        let modes = SafePreviewModes(presentation(#"{"name":"x"}"#, format: .applicationBundle, images: [icon(128)]), locale: Locale(identifier: "en"))
        let style = SafeModeStyle(typography: .init(), palette: .init(theme: .light, isDark: false, increasedContrast: false),
                                  syntaxStyle: .init(), locale: Locale(identifier: "en"))
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        view.display(modes, mode: .icon, style: style)
        let imageView = try #require(descendants(of: NSImageView.self, in: view).first)
        #expect(imageView.image != nil)
        #expect(imageView.accessibilityLabel() == PreviewStrings.text(.packageIconAccessibility))
        #expect(imageView.accessibilityRole() == .image)
        view.layoutSubtreeIfNeeded()
        #expect(imageView.frame.width <= 256 && imageView.frame.height <= 256)
        view.clear()
        #expect(imageView.image == nil)
        // A presentation without an icon leaves nothing from a previous request on screen.
        view.display(modes, mode: .icon, style: style)
        view.display(SafePreviewModes(presentation(#"{"name":"y"}"#, format: .applicationBundle), locale: Locale(identifier: "en")), mode: .icon, style: style)
        #expect(imageView.image == nil)
    }

    @Test func iconDecodingIsBoundedAndTolerantOfBadData() {
        let large = PreviewImage(data: png(1_800), pixelWidth: 1_800, pixelHeight: 1_800, role: .icon)
        let decoded = PackageIconView.decode(large)
        #expect(decoded != nil)
        #expect((decoded?.size.width ?? .infinity) <= CGFloat(PackageIconView.maximumPixelSize))
        #expect(PackageIconView.decode(PreviewImage(data: Data("not an image".utf8), pixelWidth: 4, pixelHeight: 4, role: .icon)) == nil)
    }

    @Test func nativePreviewShowsAnIconModeAndRestoresItsStateOnReplacement() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.display(.ready(presentation(#"{"name":"Synthetic","bundleIdentifier":"com.example.synthetic"}"#, format: .iosApp, images: [icon(96)])))
        let control = view.modeControl
        let titles = (0..<control.segmentCount).compactMap { control.label(forSegment: $0) }
        #expect(titles.contains(PreviewStrings.text(.previewModeIcon)) && titles.contains(PreviewStrings.text(.previewModeSummary)))
        control.selectedSegment = try #require(titles.firstIndex(of: PreviewStrings.text(.previewModeIcon)))
        #expect(control.sendAction(control.action, to: control.target))
        let iconView = try #require(descendants(of: PackageIconView.self, in: view).first)
        #expect(!iconView.isHidden && descendants(of: NSImageView.self, in: iconView).first?.image != nil)
        // Replacing the presentation with an icon-less one must not leave the old icon behind.
        view.display(.ready(presentation(#"{"name":"Other"}"#, format: .applicationBundle)), resetsContentState: true)
        #expect(descendants(of: NSImageView.self, in: iconView).first?.image == nil)
        view.display(.disabledByUser(.iosApp))
        #expect(iconView.isHidden)
    }

    // MARK: Notices

    @Test func signatureAndCertificateNoticesApplyOnlyToTheirFormats() {
        let locale = Locale(identifier: "en")
        for format in [FormatID.applicationBundle, .iosApp, .installerPackage, .provisioningProfile] {
            #expect(PresentationNotices.lines(for: presentation("{}", format: format), locale: locale).contains(PreviewStrings.text(.packageNoticeSignature)))
        }
        #expect(PresentationNotices.lines(for: presentation("{}", format: .certificate), locale: locale) == [PreviewStrings.text(.packageNoticeCertificate)])
        for format in [FormatID.torrent, .diskImage, .androidApp, .zip, .json] {
            #expect(PresentationNotices.lines(for: presentation("{}", format: format), locale: locale).isEmpty, "\(format.rawValue)")
        }
    }

    @Test func everyPackageStringResolvesInEveryShippedLanguage() throws {
        let languages = ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        let keys: [PreviewStrings.Key] = [.packageDisplayName, .packageEntitlements, .packagePrivateKeys, .packageInfoHash, .packageNoticeSignature,
                                           .packageNoticeCertificate, .packageIconAccessibility, .previewModeIcon, .packageProfileAdHoc]
        for language in languages {
            for key in keys {
                #expect(!PreviewStrings.text(key, languagePreferences: [language]).isEmpty)
            }
            if language != "en" {
                // Translated labels differ from the English draft (technical terms such as UUID aside).
                #expect(PreviewStrings.text(.packageNoticeSignature, languagePreferences: [language]) != PreviewStrings.text(.packageNoticeSignature, languagePreferences: ["en"]))
            }
        }
        for descriptor in FormatCatalog.standard.descriptors where [.applicationBundle, .iosApp, .androidApp, .provisioningProfile, .certificate, .installerPackage, .diskImage, .torrent].contains(descriptor.id) {
            for key in [descriptor.nameKey, descriptor.descriptionKey] {
                let english = PreviewStrings.text(catalogKey: key, languagePreferences: ["en"])
                #expect(!english.isEmpty && english != key)
            }
        }
    }
}
