import Foundation
import Darwin
import Testing
import PreviewContracts
@testable import PreviewFormats

/// Signature reader that returns canned facts, so privacy and layout tests need no signed bundle.
private struct StubSignatureReader: CodeSignatureReader {
    var report: CodeSignatureReport
    func read(url: URL, context: RequestContext) throws -> CodeSignatureReport { report }
}

@Suite("Application bundle summaries")
struct ApplicationBundleAdapterTests {
    private let context = PackageTestSupport.context

    private static let signed: CodeSignatureReport = {
        var summary = CodeSigningSummary(status: .signed)
        summary.identifier = "com.example.synthetic"
        summary.teamIdentifier = "ABCDE12345"
        summary.signers = ["Developer ID Application: Example (ABCDE12345)", "Developer ID Certification Authority"]
        summary.hardenedRuntime = true
        summary.appSandbox = true
        return CodeSignatureReport(summary: summary, entitlements: PlistValueSummary.entitlements([
            "com.apple.security.app-sandbox": true, "com.apple.security.network.client": true,
            "com.example.api-secret": PackageFixtures.secret, "com.example.groups": ["group.one", "group.two"]
        ]))
    }()

    /// Builds `Synthetic.app` in a fresh directory and returns its URL.
    private func makeBundle(executable: Data? = PackageFixtures.universalMachO(cpus: [PackageFixtures.arm64CPU, PackageFixtures.x86_64CPU]),
                            icon: Data? = nil, info overrides: [String: Any] = [:], flat: Bool = false) throws -> URL {
        let directory = try PackageTestSupport.temporaryDirectory()
        let bundle = directory.appendingPathComponent("Synthetic.app")
        let base = flat ? bundle : bundle.appendingPathComponent("Contents")
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: flat ? bundle : base.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: flat ? bundle : base.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        var info: [String: Any] = [
            "CFBundleName": "Synthetic", "CFBundleDisplayName": "Synthetic Display", "CFBundleIdentifier": "com.example.synthetic",
            "CFBundleShortVersionString": "3.1", "CFBundleVersion": "310", "LSMinimumSystemVersion": "13.0",
            "LSApplicationCategoryType": "public.app-category.developer-tools", "CFBundleExecutable": "Synthetic",
            "CFBundleIconFile": "AppIcon", "CFBundleDocumentTypes": [["CFBundleTypeName": "A"], ["CFBundleTypeName": "B"]],
            "CFBundleURLTypes": [["CFBundleURLSchemes": ["synthetic"]]], "NSMicrophoneUsageDescription": "Needed for tests"
        ]
        info.merge(overrides) { $1 }
        try PackageFixtures.plist(info).write(to: base.appendingPathComponent("Info.plist"))
        if let executable { try executable.write(to: (flat ? bundle : base.appendingPathComponent("MacOS")).appendingPathComponent("Synthetic")) }
        if let icon { try icon.write(to: (flat ? bundle : base.appendingPathComponent("Resources")).appendingPathComponent("AppIcon.icns")) }
        return bundle
    }

    private func adapter(_ report: CodeSignatureReport = ApplicationBundleAdapterTests.signed) -> ApplicationBundleAdapter {
        ApplicationBundleAdapter(signatureReader: StubSignatureReader(report: report))
    }

    @Test func infoArchitecturesIconSizeAndSignatureAreSummarized() throws {
        let icon = PackageFixtures.icns([("ic07", PackageFixtures.png(width: 128, height: 128)), ("ic08", PackageFixtures.png(width: 256, height: 256)),
                                         ("is32", Data(repeating: 1, count: 40))])
        let bundle = try makeBundle(icon: icon)
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let document = try adapter().parse(url: bundle, context: context)
        let summary = PackageTestSupport.object(document)
        #expect(summary["name"] as? String == "Synthetic" && summary["displayName"] as? String == "Synthetic Display")
        #expect(summary["bundleIdentifier"] as? String == "com.example.synthetic")
        #expect(summary["version"] as? String == "3.1" && summary["build"] as? String == "310")
        #expect(summary["minimumOSVersion"] as? String == "13.0")
        #expect(summary["category"] as? String == "public.app-category.developer-tools")
        #expect(summary["executable"] as? String == "Synthetic")
        #expect(summary["documentTypes"] as? Int == 2 && summary["urlSchemes"] as? Int == 1)
        #expect(summary["usageDescriptions"] as? [String] == ["NSMicrophoneUsageDescription"])
        #expect(summary["architectures"] as? [String] == ["arm64", "x86_64"] && summary["executableKind"] as? String == "universal")
        let signature = try #require(summary["signature"] as? [String: Any])
        #expect(signature["status"] as? String == "signed" && signature["signingIdentifier"] as? String == "com.example.synthetic")
        #expect(signature["teamIdentifier"] as? String == "ABCDE12345")
        #expect((signature["signers"] as? [String])?.first == "Developer ID Application: Example (ABCDE12345)")
        #expect(signature["hardenedRuntime"] as? Bool == true && signature["appSandbox"] as? Bool == true)
        #expect(signature["signatureVerified"] as? Bool == false && signature["notarizationChecked"] as? Bool == false)
        let entitlements = try #require(signature["entitlements"] as? [String: Any])
        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(entitlements["com.example.groups"] as? [String] == ["group.one", "group.two"])
        let expectedSize = try regularFileBytes(in: bundle)
        #expect(summary["bundleSize"] as? Int == expectedSize.bytes && summary["bundleItems"] as? Int == expectedSize.items)
        #expect(summary["partial"] as? Bool == false)
        let image = try #require(document.images.first)
        #expect(document.images.count == 1 && image.role == .icon && image.pixelWidth == 256 && image.isValid)
    }

    private func regularFileBytes(in url: URL) throws -> (bytes: Int, items: Int) {
        var bytes = 0
        var items = 0
        for case let child as URL in try #require(FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])) {
            items += 1
            let values = try child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values.isRegularFile == true { bytes += values.fileSize ?? 0 }
        }
        return (bytes, items)
    }

    @Test func credentialLookingEntitlementValuesAreConcealed() throws {
        let bundle = try makeBundle()
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let document = try adapter().parse(url: bundle, context: context)
        let visible = PackageTestSupport.concealedText(document)
        #expect(!visible.contains(PackageFixtures.secret))
        #expect(visible.contains("com.example.api-secret"))
        #expect(visible.contains("com.apple.security.app-sandbox"))
        #expect(document.sensitiveRanges.count >= 1 && document.usesStructuredPrivacy)
    }

    @Test func infoPropertyListStringsThatLookLikeAssignmentsAreConcealed() throws {
        let bundle = try makeBundle(info: ["CFBundleName": "password=\(PackageFixtures.secret)"])
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let document = try adapter().parse(url: bundle, context: context)
        #expect(!PackageTestSupport.concealedText(document).contains(PackageFixtures.secret))
    }

    @Test func shallowBundlesKeepTheirManifestAtTheRoot() throws {
        let bundle = try makeBundle(flat: true)
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let summary = PackageTestSupport.object(try adapter().parse(url: bundle, context: context))
        #expect(summary["bundleIdentifier"] as? String == "com.example.synthetic")
        #expect(summary["architectures"] as? [String] == ["arm64", "x86_64"])
    }

    @Test func thinExecutablesAreReportedAsSingleArchitecture() throws {
        let bundle = try makeBundle(executable: PackageFixtures.thinMachO(cpu: PackageFixtures.arm64CPU))
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let summary = PackageTestSupport.object(try adapter().parse(url: bundle, context: context))
        #expect(summary["architectures"] as? [String] == ["arm64"] && summary["executableKind"] as? String == "thin")
    }

    @Test func executableIsReadOnlyForItsHeader() throws {
        // A 6 MiB executable must not be read beyond its first 4 KiB, whatever the input allowance.
        let executable = PackageFixtures.thinMachO(cpu: PackageFixtures.x86_64CPU) + Data(repeating: 0, count: 6 * 1_048_576)
        let bundle = try makeBundle(executable: executable)
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let tight = RequestContext(budget: PreviewBudget(maxInputBytes: 16_384, maxMilliseconds: 30_000))
        let summary = PackageTestSupport.object(try adapter().parse(url: bundle, context: tight))
        #expect(summary["architectures"] as? [String] == ["x86_64"])
    }

    @Test func nonMachOExecutablesAndUnsafeNamesAreIgnored() throws {
        let script = try makeBundle(executable: Data("#!/bin/sh\necho hi\n".utf8))
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        #expect(PackageTestSupport.object(try adapter().parse(url: script, context: context))["architectures"] == nil)
        let traversal = try makeBundle(info: ["CFBundleExecutable": "../../Info.plist"])
        defer { try? FileManager.default.removeItem(at: traversal.deletingLastPathComponent()) }
        #expect(PackageTestSupport.object(try adapter().parse(url: traversal, context: context))["architectures"] == nil)
    }

    @Test func symlinkedManifestsAndIconsAreNeverFollowed() throws {
        let outside = try PackageTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        try PackageFixtures.plist(["CFBundleName": "Outside\(PackageFixtures.secret)"]).write(to: outside.appendingPathComponent("Info.plist"))
        let bundle = try makeBundle()
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let manifest = bundle.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: outside.appendingPathComponent("Info.plist"))
        #expect(throws: PreviewFailure.malformedDocument) { try adapter().parse(url: bundle, context: context) }
        // A linked intermediate directory is refused as well.
        let linked = try makeBundle()
        defer { try? FileManager.default.removeItem(at: linked.deletingLastPathComponent()) }
        try FileManager.default.removeItem(at: linked.appendingPathComponent("Contents"))
        try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("Contents"), withDestinationURL: outside)
        #expect(throws: PreviewFailure.malformedDocument) { try adapter().parse(url: linked, context: context) }
    }

    @Test func aSymlinkedBundleRootIsRefused() throws {
        let bundle = try makeBundle()
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let link = bundle.deletingLastPathComponent().appendingPathComponent("Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bundle)
        #expect(throws: PreviewFailure.unreadableFile) { try adapter().parse(url: link, context: context) }
    }

    @Test func fifosInsideTheBundleAreNeverOpened() throws {
        let bundle = try makeBundle()
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let executable = bundle.appendingPathComponent("Contents/MacOS/Synthetic")
        try FileManager.default.removeItem(at: executable)
        #expect(mkfifo(executable.path, 0o600) == 0)
        #expect(mkfifo(bundle.appendingPathComponent("Contents/Resources/AppIcon.icns").path, 0o600) == 0)
        let summary = PackageTestSupport.object(try adapter().parse(url: bundle, context: context))
        #expect(summary["architectures"] == nil && summary["name"] as? String == "Synthetic")
        let manifest = bundle.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.removeItem(at: manifest)
        #expect(mkfifo(manifest.path, 0o600) == 0)
        #expect(throws: PreviewFailure.malformedDocument) { try adapter().parse(url: bundle, context: context) }
    }

    @Test func oversizedManifestsAreRejectedAndOversizedIconsSkipped() throws {
        let large = try makeBundle(info: ["Padding": String(repeating: "x", count: ApplicationBundleAdapter.maximumInfoPropertyListBytes + 10)])
        defer { try? FileManager.default.removeItem(at: large.deletingLastPathComponent()) }
        let roomy = RequestContext(budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000))
        #expect(throws: PreviewFailure.inputTooLarge) { try adapter().parse(url: large, context: roomy) }
        let icon = PackageFixtures.icns([("ic09", PackageFixtures.png(width: 512, height: 512))]) + Data(repeating: 0, count: ApplicationBundleAdapter.maximumIconFileBytes)
        let bigIcon = try makeBundle(icon: icon)
        defer { try? FileManager.default.removeItem(at: bigIcon.deletingLastPathComponent()) }
        #expect(try adapter().parse(url: bigIcon, context: roomy).images.isEmpty)
    }

    @Test func iconTooLargeForTheRemainingAllowanceIsSkippedNotFatal() throws {
        let icon = PackageFixtures.icns([("ic09", PackageFixtures.png(width: 512, height: 512))])
        let bundle = try makeBundle(icon: icon)
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let tight = RequestContext(budget: PreviewBudget(maxInputBytes: 4_800, maxMilliseconds: 30_000))
        let document = try adapter().parse(url: bundle, context: tight)
        #expect(PackageTestSupport.object(document)["name"] as? String == "Synthetic")
    }

    @Test func notABundleIsRejectedClearly() throws {
        let directory = try PackageTestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("File.app")
        try Data("not a directory".utf8).write(to: file)
        #expect(throws: PreviewFailure.unsupportedFormat) { try adapter().parse(url: file, context: context) }
        #expect(throws: PreviewFailure.missingFile) { try adapter().parse(url: directory.appendingPathComponent("Missing.app"), context: context) }
        let empty = directory.appendingPathComponent("Empty.app")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(throws: PreviewFailure.malformedDocument) { try adapter().parse(url: empty, context: context) }
    }

    @Test func malformedManifestsFailClosed() throws {
        for content in [Data("garbage".utf8), Data("<plist><dict><key>k</key>".utf8), PackageFixtures.plist(["not", "a", "dict"])] {
            let bundle = try makeBundle()
            defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
            try content.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
            #expect(throws: PreviewFailure.self) { try adapter().parse(url: bundle, context: context) }
        }
    }

    @Test func theSourceBundleIsNeverModified() throws {
        let bundle = try makeBundle(icon: PackageFixtures.icns([("ic07", PackageFixtures.png(width: 128, height: 128))]))
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let before = try snapshot(bundle)
        _ = try adapter().parse(url: bundle, context: context)
        _ = try ApplicationBundleAdapter().parse(url: bundle, context: context)
        #expect(try snapshot(bundle) == before)
    }

    private func snapshot(_ url: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for case let child as URL in try #require(FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)) {
            var info = stat()
            lstat(child.path, &info)
            let content = info.st_mode & S_IFMT == S_IFREG ? (try Data(contentsOf: child)).base64EncodedString() : ""
            result[child.path] = "\(info.st_mode) \(info.st_mtimespec.tv_sec) \(info.st_mtimespec.tv_nsec) \(content)"
        }
        return result
    }

    @Test func cancelledRequestsNeverOpenTheBundle() async throws {
        let bundle = try makeBundle()
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let cancelled = await PackageTestSupport.parseIsCancelled { _ = try ApplicationBundleAdapter().parse(url: bundle, context: RequestContext(budget: .standard)) }
        #expect(cancelled)
    }

    // MARK: Security framework

    @Test func theSecurityReaderReportsAnUnsignedBundleWithoutFailing() throws {
        let bundle = try makeBundle()
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let report = try SecurityCodeSignatureReader().read(url: bundle, context: context)
        #expect([CodeSigningSummary.Status.unsigned, .unavailable].contains(report.summary.status))
        #expect(report.entitlements == nil && report.summary.signers.isEmpty)
        let summary = PackageTestSupport.object(try ApplicationBundleAdapter().parse(url: bundle, context: context))
        let signature = try #require(summary["signature"] as? [String: Any])
        #expect(["unsigned", "unavailable"].contains(signature["status"] as? String ?? ""))
        #expect(signature["signatureVerified"] as? Bool == false)
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/codesign")))
    func theSecurityReaderReadsAnAdHocSignatureAndEntitlements() throws {
        let bundle = try makeBundle(executable: nil)
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        let executable = bundle.appendingPathComponent("Contents/MacOS/Synthetic")
        // A platform tool copied into a scratch bundle only supplies a valid Mach-O file to sign.
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: executable.path)
        let entitlements = bundle.deletingLastPathComponent().appendingPathComponent("entitlements.plist")
        try PackageFixtures.plist(["com.apple.security.app-sandbox": true, "com.example.api-secret": PackageFixtures.secret]).write(to: entitlements)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", "--options", "runtime", "--entitlements", entitlements.path, bundle.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "codesign could not sign the scratch bundle")

        let report = try SecurityCodeSignatureReader().read(url: bundle, context: context)
        #expect(report.summary.status == .adHoc)
        #expect(report.summary.hardenedRuntime == true && report.summary.appSandbox == true)
        #expect(report.summary.identifier != nil)
        let document = try ApplicationBundleAdapter().parse(url: bundle, context: context)
        let signature = try #require(PackageTestSupport.object(document)["signature"] as? [String: Any])
        let keys = (signature["entitlements"] as? [String: Any])?.keys.sorted()
        #expect(keys == ["com.apple.security.app-sandbox", "com.example.api-secret"])
        #expect(!PackageTestSupport.concealedText(document).contains(PackageFixtures.secret))
        #expect(PackageTestSupport.object(document)["architectures"] != nil)
    }
}
