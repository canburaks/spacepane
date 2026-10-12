import Darwin
import Foundation
import PreviewContracts
import PreviewPreferences
import UniformTypeIdentifiers

private struct SettingsCheckFailure: Error, CustomStringConvertible {
    let description: String
}

/// Settings workstream checks over the production companion models. Storage and every scanned bundle live in
/// a temporary directory created for the run: no user preference, installed app or Finder state is read.
@MainActor
enum SettingsModelChecks {
    static func run(in root: URL) async throws {
        try await behaviorChoicesPersistAndStayIndependent(root)
        try await schemeChoicesPersistAndRejectMismatches(root)
        try await schemaFiveStoreMigratesWithoutWritingAndRepublishesSchemaSix(root)
        try await outOfRangeFolderDepthRecoversFailClosed(root)
        try await scannerFindsOverlappingExtensionsInSyntheticBundles(root)
        try await scannerHonorsBoundsLinksAndAccessDenial(root)
        try await scannerHonorsCancellation(root)
        try await diagnosticsModelDropsLateAndCancelledResults()
        print("Passed 8 settings model checks (temporary storage and synthetic bundles; no installed app, Finder or UI).")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw SettingsCheckFailure(description: message) }
    }

    private static func eventually(_ message: String, _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw SettingsCheckFailure(description: message) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Preferences

    private static func behaviorChoicesPersistAndStayIndependent(_ root: URL) async throws {
        let url = root.appendingPathComponent("behavior-preferences.json")
        let store = PreferenceStore(url: url)
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        let defaults = settings.snapshot
        try check(defaults.reloadsOnFileChange && defaults.showsContentThumbnails && defaults.folderDepth == 1
                  && !defaults.showsHiddenFolderItems, "Fresh settings must carry the documented behavior defaults")
        settings.setEnabled(false, for: .json)
        settings.setTheme(.dark)
        settings.setReloadsOnFileChange(false)
        settings.setShowsContentThumbnails(false)
        settings.setFolderDepth(3)
        settings.setShowsHiddenFolderItems(true)
        try await eventually("Behavior choices did not save") { settings.saveState == .saved }
        let loaded = await PreferenceStore(url: url).load()
        try check(loaded.state == .loaded && loaded.snapshot == settings.snapshot,
                  "Every behavior choice must persist in one complete snapshot")
        try check(!loaded.snapshot.reloadsOnFileChange && !loaded.snapshot.showsContentThumbnails
                  && loaded.snapshot.folderDepth == 3 && loaded.snapshot.showsHiddenFolderItems,
                  "A fresh reader must observe the saved behavior choices")
        try check(loaded.snapshot.requestOptions == PreviewRequestOptions(folderDepth: 3, includesHiddenItems: true),
                  "The reader's request options must follow the saved folder choices")
        try check(!loaded.snapshot.isEnabled(.json) && loaded.snapshot.theme == .dark,
                  "Behavior changes must preserve file-type choices and appearance")
        // The stepper range is enforced by the model, not only by the control.
        settings.setFolderDepth(0)
        try check(settings.snapshot.folderDepth == 1, "Depth below the range must clamp to 1")
        settings.setFolderDepth(99)
        try check(settings.snapshot.folderDepth == 4, "Depth above the range must clamp to 4")
        settings.setFolderDepth(2)
        try check(settings.snapshot.folderDepth == 2, "A depth inside the range must be kept")
        var publications = 0
        let observer = settings.observe { _ in publications += 1 }
        defer { settings.removeObserver(observer) }
        let revision = settings.appearanceRevision
        settings.setFolderDepth(2)
        settings.setReloadsOnFileChange(false)
        try check(publications == 0, "Repeating the saved value must not publish")
        settings.setReloadsOnFileChange(true)
        try check(publications == 1 && settings.appearanceRevision == revision,
                  "A behavior change must not count as an appearance edit")
        try await eventually("Second behavior save did not finish") { settings.saveState == .saved }
    }

    private static func schemeChoicesPersistAndRejectMismatches(_ root: URL) async throws {
        let url = root.appendingPathComponent("scheme-preferences.json")
        let store = PreferenceStore(url: url)
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        settings.setEnabled(false, for: .json)
        settings.setReloadsOnFileChange(false)
        let revision = settings.appearanceRevision
        settings.setLightScheme(.nord)
        settings.setDarkScheme(.paper)
        try check(settings.snapshot.syntaxStyle == PreviewSyntaxStyle() && settings.appearanceRevision == revision,
                  "A scheme for the wrong appearance must be ignored")
        settings.setLightScheme(.solarizedLight)
        settings.setDarkScheme(.dracula)
        try check(settings.snapshot.syntaxStyle.lightScheme == .solarizedLight && settings.snapshot.syntaxStyle.darkScheme == .dracula
                  && settings.appearanceRevision > revision, "Valid scheme choices must apply and count as appearance edits")
        // Schemes are part of the transferable appearance, so a saved profile restores both of them.
        settings.saveAppearanceProfile(name: "With Schemes")
        guard let profile = settings.snapshot.appearanceProfiles.first else { throw SettingsCheckFailure(description: "Profile was not saved") }
        settings.resetAppearance()
        try check(settings.snapshot.syntaxStyle == PreviewSyntaxStyle(), "Reset Appearance must restore the Standard schemes")
        try check(!settings.snapshot.reloadsOnFileChange && !settings.isEnabled(.json),
                  "Reset Appearance must not change behavior or file-type choices")
        settings.applyAppearanceProfile(id: profile.id)
        try check(settings.snapshot.syntaxStyle.lightScheme == .solarizedLight && settings.snapshot.syntaxStyle.darkScheme == .dracula,
                  "Applying a profile must restore its schemes")
        try await eventually("Scheme choices did not save") { settings.saveState == .saved }
        let loaded = await PreferenceStore(url: url).load()
        try check(loaded.state == .loaded && loaded.snapshot == settings.snapshot, "Schemes and profiles must persist together")
        // A theme file carries the schemes and nothing else; an imported version 1 file selects Standard.
        let exported = try AppearanceThemeCodec.encode(settings.snapshot.appearance)
        let imported = try AppearanceThemeCodec.decode(exported)
        try check(imported == settings.snapshot.appearance, "A theme must round trip its schemes")
    }

    private static func schemaFiveStoreMigratesWithoutWritingAndRepublishesSchemaSix(_ root: URL) async throws {
        let url = root.appendingPathComponent("schema-five-preferences.json")
        let profileID = UUID().uuidString
        let typography: [String: Any] = ["fontSize": 17, "wrapsLines": true, "fontFamily": NSNull(), "weight": "regular",
            "italic": false, "lineSpacing": 0, "characterSpacing": 0, "ligatures": true, "tabWidth": 4, "showsLineNumbers": false]
        let document: [String: Any] = [
            "schemaVersion": 5, "defaultEnabled": false, "formatOverrides": ["data.json": true], "theme": "light",
            "typography": typography,
            "syntaxStyle": ["usesColor": true, "boldRoles": ["key"], "italicRoles": []],
            "appearanceProfiles": [["id": profileID, "name": "Old Profile",
                "appearance": ["typography": typography, "theme": "dark",
                               "syntaxStyle": ["usesColor": true, "boldRoles": [], "italicRoles": ["comment"]]]]]
        ]
        let original = try JSONSerialization.data(withJSONObject: document, options: .sortedKeys)
        try original.write(to: url)
        let store = PreferenceStore(url: url)
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        let snapshot = settings.snapshot
        try check(!settings.recoveredSettings && !snapshot.defaultEnabled && snapshot.isEnabled(.json) && snapshot.theme == .light,
                  "A schema 5 file must migrate with its file-type choices and theme")
        try check(snapshot.reloadsOnFileChange && snapshot.showsContentThumbnails && snapshot.folderDepth == 1
                  && !snapshot.showsHiddenFolderItems && snapshot.syntaxStyle.lightScheme == .standard
                  && snapshot.syntaxStyle.darkScheme == .standard && snapshot.syntaxStyle.boldRoles == [.key],
                  "Only the fields schema 5 lacked may take defaults")
        try check(snapshot.appearanceProfiles.map(\.name) == ["Old Profile"]
                  && snapshot.appearanceProfiles.first?.appearance.syntaxStyle.italicRoles == [.comment],
                  "Saved profiles must migrate with their syntax traits")
        let afterLoad = try Data(contentsOf: url)
        try check(afterLoad == original, "Loading must not write a migrated file")
        settings.setShowsHiddenFolderItems(true)
        try await eventually("Migrated settings did not save") { settings.saveState == .saved }
        guard let published = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw SettingsCheckFailure(description: "Published settings are not a JSON object")
        }
        try check(published["schemaVersion"] as? Int == 6 && published["showsHiddenFolderItems"] as? Bool == true
                  && published["reloadsOnFileChange"] as? Bool == true, "The first save must publish schema 6")
        let reloaded = await PreferenceStore(url: url).load()
        try check(reloaded.state == .loaded && reloaded.snapshot == settings.snapshot, "The republished file must load as current")
    }

    private static func outOfRangeFolderDepthRecoversFailClosed(_ root: URL) async throws {
        let url = root.appendingPathComponent("bad-depth-preferences.json")
        let store = PreferenceStore(url: url)
        try await store.save(PreviewPreferencesSnapshot(folderDepth: 2))
        guard var object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw SettingsCheckFailure(description: "Saved settings are not a JSON object")
        }
        object["folderDepth"] = 9
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let settings = CompanionSettings(store: store, storageMode: .privateOnly)
        await settings.load()
        try check(settings.recoveredSettings && settings.snapshot == .disabledContentFallback,
                  "An out-of-range stored depth must be corrupt storage that fails closed")
        settings.setFolderDepth(2)
        try await eventually("Repair did not save") { settings.saveState == .saved }
        let repaired = await PreferenceStore(url: url).load()
        try check(repaired.state == .loaded && repaired.snapshot.folderDepth == 2 && !repaired.snapshot.isEnabled(.json)
                  && !settings.recoveredSettings, "An explicit choice repairs storage without re-enabling file types")
    }

    // MARK: Provider scan

    private struct SyntheticApp {
        var name: String
        var identifier: String?
        var appName: String?
        var extensions: [Extension] = []
        struct Extension {
            var point: String?
            var types: [String]
            var directory = "Ext.appex"
        }
    }

    private static let previewPoint = "com.apple.quicklook.preview"
    private static let thumbnailPoint = "com.apple.quicklook.thumbnail"

    private static func writePlist(_ object: Any, to url: URL, format: PropertyListSerialization.PropertyListFormat = .xml) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: object, format: format, options: 0).write(to: url)
    }

    @discardableResult
    private static func makeApp(_ bundle: SyntheticApp, in root: URL) throws -> URL {
        let app = root.appendingPathComponent(bundle.name, isDirectory: true)
        var info: [String: Any] = [:]
        if let identifier = bundle.identifier { info["CFBundleIdentifier"] = identifier }
        if let appName = bundle.appName { info["CFBundleName"] = appName }
        try writePlist(info, to: app.appendingPathComponent("Contents/Info.plist"))
        for item in bundle.extensions {
            var extensionInfo: [String: Any] = [:]
            if let point = item.point {
                extensionInfo["NSExtension"] = ["NSExtensionPointIdentifier": point,
                                                "NSExtensionAttributes": ["QLSupportedContentTypes": item.types]]
            }
            try writePlist(extensionInfo, to: app.appendingPathComponent("Contents/PlugIns/\(item.directory)/Contents/Info.plist"),
                           format: .binary)
        }
        return app
    }

    private static func firstType(_ id: FormatID) throws -> String {
        guard let type = FormatCatalog.standard.descriptor(for: id)?.contentTypes.first else {
            throw SettingsCheckFailure(description: "Missing catalog type for \(id.rawValue)")
        }
        return type.identifier
    }

    private static func scannerFindsOverlappingExtensionsInSyntheticBundles(_ root: URL) async throws {
        let applications = root.appendingPathComponent("scan-a/Applications", isDirectory: true)
        let json = try firstType(.json)
        try makeApp(SyntheticApp(name: "Alpha.app", identifier: "com.example.alpha", appName: "Alpha Viewer",
            extensions: [.init(point: previewPoint, types: [json, "com.example.unrelated"], directory: "AlphaPreview.appex"),
                         .init(point: thumbnailPoint, types: [json.uppercased()], directory: "AlphaThumb.appex")]), in: applications)
        // A subtype of public.source-code overlaps by conformance although the identifiers differ.
        try makeApp(SyntheticApp(name: "Beta.app", identifier: "com.example.beta", appName: nil,
            extensions: [.init(point: thumbnailPoint, types: ["public.swift-source"])]), in: applications)
        // The abstract root public.data matches only the one format that declares it, never every subtype of it.
        try makeApp(SyntheticApp(name: "Gamma.app", identifier: "com.example.gamma", appName: "Gamma",
            extensions: [.init(point: previewPoint, types: ["public.data", "public.item", "public.content"])]), in: applications)
        // Present but unrelated, wrong extension point, no extension at all: scanned, never reported.
        try makeApp(SyntheticApp(name: "Delta.app", identifier: "com.example.delta", appName: "Delta",
            extensions: [.init(point: previewPoint, types: ["com.example.unrelated"])]), in: applications)
        try makeApp(SyntheticApp(name: "Share.app", identifier: "com.example.share", appName: "Share",
            extensions: [.init(point: "com.apple.share-services", types: [json])]), in: applications)
        try makeApp(SyntheticApp(name: "Plain.app", identifier: "com.example.plain", appName: "Plain"), in: applications)
        // This app itself is excluded by identifier even though it declares an overlapping type.
        try makeApp(SyntheticApp(name: "Self.app", identifier: "com.example.self", appName: "Self",
            extensions: [.init(point: previewPoint, types: [json])]), in: applications)
        // A malformed bundle plist leaves the file name as the displayed name.
        let quirky = try makeApp(SyntheticApp(name: "Quirky Name.app", identifier: nil, appName: nil,
            extensions: [.init(point: previewPoint, types: [json])]), in: applications)
        try Data("not a property list".utf8).write(to: quirky.appendingPathComponent("Contents/Info.plist"))
        // Things that are not applications at this level.
        try FileManager.default.createDirectory(at: applications.appendingPathComponent("Folder", isDirectory: true), withIntermediateDirectories: true)
        try Data("text".utf8).write(to: applications.appendingPathComponent("readme.txt"))
        let nested = applications.appendingPathComponent("Utilities", isDirectory: true)
        try makeApp(SyntheticApp(name: "Nested.app", identifier: "com.example.nested", appName: "Nested",
            extensions: [.init(point: previewPoint, types: [json])]), in: nested)
        let missing = root.appendingPathComponent("scan-a/Missing", isDirectory: true)

        let scanner = QuickLookProviderScanner(
            roots: [.init(url: applications, label: "/Applications"), .init(url: missing, label: "~/Applications")],
            excludedBundleIdentifiers: ["com.example.self"])
        let report = try await scanner.scan()
        try check(report.unreadableLocations.isEmpty, "A folder that does not exist is skipped silently, not reported as denied")
        try check(!report.reachedApplicationLimit && report.skippedApplications == 0, "Nothing should be skipped in the synthetic tree")
        try check(report.scannedApplications == 8, "Only immediate .app children are inspected (got \(report.scannedApplications))")
        let names = report.providers.map(\.name)
        try check(names == ["Alpha Viewer", "Beta", "Gamma", "Quirky Name"],
                  "Reported apps must be exactly those with an overlapping Quick Look extension, sorted by name: \(names)")
        let byName = Dictionary(uniqueKeysWithValues: report.providers.map { ($0.name, $0) })
        try check(byName["Alpha Viewer"]?.kinds == [.preview, .thumbnail], "Alpha declares both a preview and a thumbnail extension")
        // Other formats that build on JSON (for example HAR or GeoJSON) may join the overlap as the
        // catalog grows; the formats that declare public.json must stay, and the list must stay in
        // catalog order. The notebook joins only where its type conforms to public.json on this host: a
        // Mac on which another app declares org.jupyter.ipynb resolves that app's declaration, not the
        // catalog's imported one (seen on the hosted runner).
        let alphaOverlap = byName["Alpha Viewer"]?.overlappingFormats ?? []
        let catalogOrder = FormatCatalog.standard.descriptors.map(\.id)
        var requiredOverlap: Set<FormatID> = [.json, .packageJSON]
        if FormatCatalog.standard.descriptor(for: .jupyterNotebook)?.canonicalContentType.conforms(to: .json) == true {
            requiredOverlap.insert(.jupyterNotebook)
        }
        try check(requiredOverlap.isSubset(of: Set(alphaOverlap))
                  && alphaOverlap == catalogOrder.filter(Set(alphaOverlap).contains),
                  "public.json overlaps the formats that declare it and the types that conform to it on this host, in catalog order: \(alphaOverlap)")
        try check(byName["Alpha Viewer"]?.bundleIdentifier == "com.example.alpha", "The bundle identifier is read")
        try check(byName["Beta"]?.kinds == [.thumbnail] && byName["Beta"]?.overlappingFormats == [.plainText, .sourceCode],
                  "A Swift source type conforms to the plain-text and source-code types this app declares")
        try check(byName["Gamma"]?.overlappingFormats == [.extensionlessText],
                  "public.data matches only the extension-free format exactly; public.item and public.content match nothing")
        try check(byName["Quirky Name"]?.name == "Quirky Name" && byName["Quirky Name"]?.bundleIdentifier == nil,
                  "A missing or malformed name falls back to the bundle file name")
        try check(!names.contains("Self") && !names.contains("Nested"), "The own app and deeper levels must not be reported")
        try check(report.providers.allSatisfy { $0.id.hasPrefix(applications.path) }, "Each result is identified by its bundle path")
    }

    private static func scannerHonorsBoundsLinksAndAccessDenial(_ root: URL) async throws {
        let base = root.appendingPathComponent("scan-b", isDirectory: true)
        let applications = base.appendingPathComponent("Applications", isDirectory: true)
        let json = try firstType(.json)
        let fileManager = FileManager.default
        // Linked app: ignored entirely.
        let real = try makeApp(SyntheticApp(name: "Real.app", identifier: "com.example.real", appName: "Real",
            extensions: [.init(point: previewPoint, types: [json])]), in: applications)
        try fileManager.createSymbolicLink(at: applications.appendingPathComponent("Linked.app"), withDestinationURL: real)
        // PlugIns reached through a link and a linked .appex are never followed.
        let outside = base.appendingPathComponent("Outside", isDirectory: true)
        try makeApp(SyntheticApp(name: "Source.app", identifier: nil, appName: nil,
            extensions: [.init(point: previewPoint, types: [json])]), in: outside)
        let viaPlugIns = try makeApp(SyntheticApp(name: "ViaPlugIns.app", identifier: "com.example.via", appName: "Via", extensions: []), in: applications)
        try fileManager.createSymbolicLink(at: viaPlugIns.appendingPathComponent("Contents/PlugIns"),
                                           withDestinationURL: outside.appendingPathComponent("Source.app/Contents/PlugIns"))
        let viaAppex = try makeApp(SyntheticApp(name: "ViaAppex.app", identifier: "com.example.appex", appName: "ViaAppex", extensions: []), in: applications)
        try fileManager.createDirectory(at: viaAppex.appendingPathComponent("Contents/PlugIns"), withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: viaAppex.appendingPathComponent("Contents/PlugIns/Linked.appex"),
                                           withDestinationURL: outside.appendingPathComponent("Source.app/Contents/PlugIns/Ext.appex"))
        // An extension plist over the cap is skipped for that extension; the app is still counted as inspected.
        let limits = QuickLookProviderScanner.Limits(maximumApplications: 2_000, maximumEntriesPerDirectory: 20_000,
            maximumExtensionsPerApplication: 32, maximumPropertyListBytes: 4_096)
        let huge = try makeApp(SyntheticApp(name: "Huge.app", identifier: "com.example.huge", appName: "Huge", extensions: []), in: applications)
        let padding = String(repeating: "x", count: limits.maximumPropertyListBytes * 2)
        try writePlist(["NSExtension": ["NSExtensionPointIdentifier": previewPoint,
                                        "NSExtensionAttributes": ["QLSupportedContentTypes": [json], "Padding": padding]]],
                       to: huge.appendingPathComponent("Contents/PlugIns/Big.appex/Contents/Info.plist"))
        // A bundle without Contents cannot be inspected and is counted as skipped.
        try fileManager.createDirectory(at: applications.appendingPathComponent("Broken.app", isDirectory: true), withIntermediateDirectories: true)

        let scanner = QuickLookProviderScanner(roots: [.init(url: applications, label: "/Applications")], limits: limits)
        let report = try await scanner.scan()
        try check(report.providers.map(\.name) == ["Real"], "Only the real, unlinked app with a readable extension is reported: \(report.providers.map(\.name))")
        try check(report.scannedApplications == 4 && report.skippedApplications == 1,
                  "Links are not counted, bundles are inspected or skipped (scanned \(report.scannedApplications), skipped \(report.skippedApplications))")

        // The application bound stops the scan and says so.
        var tight = limits
        tight.maximumApplications = 2
        let bounded = try await QuickLookProviderScanner(roots: [.init(url: applications, label: "/Applications")], limits: tight).scan()
        try check(bounded.reachedApplicationLimit && bounded.scannedApplications + bounded.skippedApplications == 2,
                  "The application limit must bound the work and be reported")

        // A denied folder is reported by label while the readable one is still scanned.
        let denied = base.appendingPathComponent("Denied", isDirectory: true)
        try fileManager.createDirectory(at: denied, withIntermediateDirectories: true)
        guard chmod(denied.path, 0o000) == 0 else { throw SettingsCheckFailure(description: "Could not remove access for the fixture") }
        defer { chmod(denied.path, 0o755) }
        if geteuid() != 0 {
            let partial = try await QuickLookProviderScanner(roots: [.init(url: denied, label: "~/Applications"),
                                                                   .init(url: applications, label: "/Applications")], limits: limits).scan()
            try check(partial.unreadableLocations == ["~/Applications"], "A folder that cannot be listed must be named in the result")
            try check(partial.providers.map(\.name) == ["Real"], "A denied folder must not stop the readable folders")
        }
        // The standard roots name the three documented folders and no others.
        let labels = QuickLookProviderScanner.standardRoots().map(\.label)
        try check(labels.prefix(2) == ["/Applications", "/System/Applications"] && labels.dropFirst(2).allSatisfy { $0 == "~/Applications" },
                  "Only the documented root folders may be scanned")
    }

    private static func scannerHonorsCancellation(_ root: URL) async throws {
        let applications = root.appendingPathComponent("scan-c/Applications", isDirectory: true)
        for index in 0..<20 {
            try makeApp(SyntheticApp(name: "App\(index).app", identifier: "com.example.app\(index)", appName: "App \(index)"), in: applications)
        }
        let scanner = QuickLookProviderScanner(roots: [.init(url: applications, label: "/Applications")])
        // The task cancels itself before it enters the scanner, so the first checkpoint must stop the scan.
        let task = Task<QuickLookProviderReport, any Error> {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await scanner.scan()
        }
        do {
            _ = try await task.value
            throw SettingsCheckFailure(description: "A cancelled scan must not return a report")
        } catch is CancellationError {}
        let complete = try await scanner.scan()
        try check(complete.scannedApplications == 20, "A later scan must start fresh and complete")
    }

    // MARK: Diagnostics model

    private static func diagnosticsModelDropsLateAndCancelledResults() async throws {
        func report(_ count: Int) -> QuickLookProviderReport { QuickLookProviderReport(scannedApplications: count) }
        let counter = CallCounter()
        let diagnostics = QuickLookProviderDiagnostics(scan: {
            // The first scan is slow and the second fast, so the first result arrives late.
            let call = await counter.next()
            try await Task.sleep(for: .milliseconds(call == 1 ? 300 : 10))
            return QuickLookProviderReport(scannedApplications: call)
        })
        try check(diagnostics.state == .idle && !diagnostics.isScanning, "No scan runs until the user asks for one")
        diagnostics.startScan()
        try check(diagnostics.isScanning, "Starting must show the scanning state at once")
        diagnostics.startScan()
        try await eventually("Replacement scan did not finish") { diagnostics.state != .scanning }
        try check(diagnostics.state == .finished(report(2)), "Only the latest scan may publish")
        try await Task.sleep(for: .milliseconds(400))
        try check(diagnostics.state == .finished(report(2)), "A late result from a replaced scan must be dropped")

        // Cancel: the running scan stops, state returns to the start and a late result changes nothing.
        let slow = QuickLookProviderDiagnostics(scan: {
            try await Task.sleep(for: .milliseconds(300))
            return QuickLookProviderReport(scannedApplications: 9)
        })
        slow.startScan()
        slow.cancel()
        try check(slow.state == .idle, "Cancel must return to the starting state")
        try await Task.sleep(for: .milliseconds(450))
        try check(slow.state == .idle, "A cancelled scan must never publish")

        // A scan that fails also returns to the starting state instead of showing a partial result.
        struct Failure: Error {}
        let failing = QuickLookProviderDiagnostics(scan: { throw Failure() })
        failing.startScan()
        try await eventually("Failed scan did not settle") { failing.state != .scanning }
        try check(failing.state == .idle, "A failed scan must not show a result")
    }

    private actor CallCounter {
        private var calls = 0
        func next() -> Int { calls += 1; return calls }
    }
}
