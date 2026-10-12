import Foundation
import Synchronization
import Testing
import UniformTypeIdentifiers
import PreviewContracts
import PreviewCore
import PreviewFormats

/// Pipeline-level checks for the package, certificate, disk-image and torrent formats: routing by
/// suffix, the user's enable switch, end-to-end concealment and read-only behavior. Adapter-level
/// parsing is covered in PreviewFormatsTests; the adversarial corpus run by `--test` feeds a synthetic
/// file of every one of these formats through this same pipeline.
@Suite("Package formats through the pipeline")
struct PackagePipelineTests {
    private static let secret = "synthetic-secret-value"
    private static let packageFormats: [FormatID] = [.applicationBundle, .iosApp, .androidApp, .provisioningProfile, .certificate,
                                                     .installerPackage, .diskImage, .torrent]
    private let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)

    private func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("package-pipeline-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: Catalog and routing

    @Test func everyPackageFormatIsCatalogedRegisteredAndPolicyChecked() {
        let catalog = FormatCatalog.standard
        let registered = Set(StandardFormatAdapters.registrations.map(\.formatID))
        for id in Self.packageFormats {
            let descriptor = catalog.descriptor(for: id)
            #expect(descriptor != nil && registered.contains(id), "\(id.rawValue)")
            #expect(descriptor?.defaultEnabled == true)
            // No catch-all type may ever be claimed.
            #expect(descriptor?.contentTypes.allSatisfy { ![UTType.data, .item, .content].contains($0) } == true)
        }
    }

    @Test func thumbnailPolicyIsContentOnlyWhereAnIconOrCoverIsMeaningful() {
        let catalog = FormatCatalog.standard
        let content: Set<FormatID> = [.applicationBundle, .iosApp]
        for id in Self.packageFormats {
            #expect(catalog.descriptor(for: id)?.thumbnail == (content.contains(id) ? .content : .generic), "\(id.rawValue)")
        }
    }

    @Test(arguments: [
        ("Example.app", FormatID.applicationBundle), ("Example.ipa", .iosApp), ("example.apk", .androidApp), ("bundle.aab", .androidApp),
        ("a.mobileprovision", .provisioningProfile), ("a.provisionprofile", .provisioningProfile),
        ("a.cer", .certificate), ("a.crt", .certificate), ("a.der", .certificate), ("a.pem", .certificate),
        ("Installer.pkg", .installerPackage), ("Disk.dmg", .diskImage), ("Linux.torrent", .torrent),
        ("UPPER.IPA", .iosApp), ("CERT.PEM", .certificate)
    ])
    func suffixesRouteToThePackageFormats(name: String, expected: FormatID) {
        #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/tmp/" + name)) == expected)
    }

    @Test func systemTypesRouteWhereTheSuffixIsAbsent() {
        let catalog = FormatCatalog.standard
        let item = URL(fileURLWithPath: "/tmp/untyped")
        #expect(catalog.classify(url: item, contentType: UTType("com.apple.application-bundle")) == .applicationBundle)
        #expect(catalog.classify(url: item, contentType: UTType("com.apple.installer-package-archive")) == .installerPackage)
        #expect(catalog.classify(url: item, contentType: UTType("com.apple.disk-image-udif")) == .diskImage)
        #expect(catalog.classify(url: item, contentType: UTType("public.x509-certificate")) == .certificate)
        // An imported type: a test process declares none, so it is constructed the way the catalog does.
        #expect(catalog.classify(url: item, contentType: UTType(importedAs: "org.bittorrent.torrent")) == .torrent)
        #expect(catalog.classify(url: item, contentType: UTType("com.apple.itunes.ipa")) == .iosApp)
    }

    @Test func packageSuffixesDoNotCaptureOtherFormats() {
        let catalog = FormatCatalog.standard
        for name in ["a.zip", "a.jar", "a.xip", "a.tar", "a.gz", "a.json", "a.txt", "a.plist", "a.sqlite"] {
            #expect(!Self.packageFormats.contains(catalog.classify(url: URL(fileURLWithPath: "/tmp/" + name)) ?? .plainText), "\(name)")
        }
    }

    // MARK: Enable switch

    @Test func disabledPackageTypesNeverReadOrConstructAnAdapter() async {
        struct Unreadable: PreviewFileReading {
            func read(url: URL, context: RequestContext) throws -> FileBytes { Issue.record("Disabled type read"); throw PreviewFailure.unreadableFile }
            func openRandomAccess(url: URL, context: RequestContext) throws -> any PreviewByteSource { Issue.record("Disabled type opened"); throw PreviewFailure.unreadableFile }
        }
        let constructed = Mutex(0)
        let registrations = [
            AdapterRegistration(formatID: .applicationBundle, urlAdapter: { constructed.withLock { $0 += 1 }; return ApplicationBundleAdapter() }),
            AdapterRegistration(formatID: .iosApp, randomAccessAdapter: { constructed.withLock { $0 += 1 }; return IOSApplicationAdapter() }),
            AdapterRegistration(formatID: .certificate, binaryAdapter: { constructed.withLock { $0 += 1 }; return CertificateAdapter() })
        ]
        let pipeline = PreviewPipeline(registrations: registrations, reader: Unreadable())
        for (name, id) in [("a.app", FormatID.applicationBundle), ("a.ipa", .iosApp), ("a.pem", .certificate)] {
            var preferences = PreviewPreferencesSnapshot.defaults
            preferences.setEnabled(false, for: id)
            #expect(await pipeline.preview(url: URL(fileURLWithPath: "/never-read/" + name), preferences: preferences) == .disabledByUser(id))
            #expect(await pipeline.inspect(url: URL(fileURLWithPath: "/never-read/" + name), preferences: preferences) == .disabledByUser(id))
        }
        #expect(constructed.withLock { $0 } == 0)
    }

    @Test func disablingOnePackageTypeLeavesTheOthersEnabled() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let torrent = directory.appendingPathComponent("a.torrent")
        try Self.torrent().write(to: torrent)
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .certificate)
        guard case .ready(let presentation) = await pipeline.preview(url: torrent, preferences: preferences) else { Issue.record("Expected torrent preview"); return }
        #expect(presentation.formatID == .torrent)
    }

    @Test func aDisabledTypeDoesNotFallBackToGenericText() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pem = directory.appendingPathComponent("key.pem")
        try Data(("-----BEGIN PRIVATE KEY-----\n" + String(repeating: "QUJD", count: 20) + "\n-----END PRIVATE KEY-----\n").utf8).write(to: pem)
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .certificate)
        #expect(await pipeline.preview(url: pem, preferences: preferences) == .disabledByUser(.certificate))
    }

    // MARK: End to end

    private static func torrent(comment: String = "Ordinary note") -> Data {
        let info = "d6:lengthi10e4:name4:file12:piece lengthi16384e6:pieces20:" + String(repeating: "A", count: 20) + "e"
        let root = "d8:announce\(("udp://tracker.example.test:6969/announce?passkey=" + secret).count):udp://tracker.example.test:6969/announce?passkey=\(secret)"
            + "7:comment\(comment.count):\(comment)4:info\(info)e"
        return Data(root.utf8)
    }

    @Test func torrentPipelineConcealsEveryRepresentationAndNeverWrites() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("synthetic.torrent")
        try Self.torrent(comment: "password=\(Self.secret)").write(to: url)
        let before = try Data(contentsOf: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard case .ready(let presentation) = await pipeline.preview(url: url) else { Issue.record("Expected torrent preview"); return }
        #expect(presentation.formatID == .torrent && presentation.syntax == .json)
        #expect(!presentation.text.contains(Self.secret) && !presentation.text.contains("passkey"))
        #expect(presentation.redactionCount >= 1)
        #expect(presentation.text.contains("udp://tracker.example.test:6969"))
        #expect((try JSONSerialization.jsonObject(with: Data(presentation.text.utf8))) is [String: Any])
        #expect(try Data(contentsOf: url) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["synthetic.torrent"])
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == attributes[.modificationDate] as? Date)
    }

    @Test func privateKeyPEMFilesPreviewWithoutAnyKeyMaterial() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("server.pem")
        let body = Data("\(Self.secret)-key-body".utf8).base64EncodedString()
        try Data("-----BEGIN RSA PRIVATE KEY-----\n\(body)\n-----END RSA PRIVATE KEY-----\n".utf8).write(to: url)
        guard case .ready(let presentation) = await pipeline.preview(url: url) else { Issue.record("Expected certificate preview"); return }
        #expect(presentation.formatID == .certificate)
        #expect(!presentation.text.contains(Self.secret) && !presentation.text.contains(body) && !presentation.text.contains("-----"))
        #expect(presentation.text.contains("RSA PRIVATE KEY"))
        #expect(presentation.redactionCount == 0)
    }

    @Test func profileSummariesConcealCredentialLookingEntitlementValues() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("synthetic.mobileprovision")
        let profile: [String: Any] = ["Name": "Synthetic", "TeamName": "Example", "UUID": "00000000-0000-4000-8000-000000000002",
                                      "ProvisionedDevices": ["synthetic-device-1"],
                                      "Entitlements": ["com.example.api-secret": Self.secret, "get-task-allow": true]]
        try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0).write(to: url)
        guard case .ready(let presentation) = await pipeline.preview(url: url) else { Issue.record("Expected profile preview"); return }
        #expect(presentation.formatID == .provisioningProfile)
        #expect(!presentation.text.contains(Self.secret) && !presentation.text.contains("synthetic-device-1"))
        #expect(presentation.text.contains("com.example.api-secret") && presentation.redactionCount >= 1)
    }

    @Test func applicationBundlesPreviewThroughTheDirectoryPathWithoutChangingTheBundle() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = directory.appendingPathComponent("Synthetic.app")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleName": "password=\(Self.secret)", "CFBundleIdentifier": "com.example.synthetic", "CFBundleExecutable": "Synthetic"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        try Data("not a mach-o".utf8).write(to: bundle.appendingPathComponent("Contents/MacOS/Synthetic"))
        func snapshot() throws -> [String] {
            try FileManager.default.subpathsOfDirectory(atPath: bundle.path).sorted().map { path in
                let attributes = try FileManager.default.attributesOfItem(atPath: bundle.appendingPathComponent(path).path)
                return "\(path) \(attributes[.size] ?? 0) \(attributes[.modificationDate] ?? Date.distantPast)"
            }
        }
        let before = try snapshot()
        guard case .ready(let presentation) = await pipeline.preview(url: bundle) else { Issue.record("Expected application preview"); return }
        #expect(presentation.formatID == .applicationBundle)
        #expect(presentation.text.contains("com.example.synthetic"))
        #expect(!presentation.text.contains(Self.secret))
        #expect(try snapshot() == before)
    }

    @Test func malformedPackageFilesFailWithTypedErrorsNotFallbackText() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["bad.torrent", "bad.pkg", "bad.dmg", "bad.apk", "bad.ipa", "bad.cer", "bad.mobileprovision"] {
            let url = directory.appendingPathComponent(name)
            try Data(repeating: 0x41, count: 600).write(to: url)
            guard case .unavailable = await pipeline.preview(url: url) else { Issue.record("\(name) must not preview as text"); continue }
        }
    }
}
