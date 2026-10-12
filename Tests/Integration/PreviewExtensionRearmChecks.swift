import AppKit
import Foundation
import PreviewContracts
import PreviewCore

@main @MainActor
struct PreviewExtensionRearmChecks {
    private struct Failure: Error { let message: String }
    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(message: message) }
    }
    static func main() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("extension-rearm-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("synthetic.txt"), bytes = Data("ordinary synthetic content".utf8)
        try bytes.write(to: source)
        let request = PreviewViewController.LiveSource(url: source, preferencesURL: root.appendingPathComponent("settings.json"))
        var failures: [String] = []
        do { try failedStartIsNotRemembered(request) } catch { failures.append("start: \(error)") }
        do { try terminalReloadIsNotRemembered(request) } catch { failures.append("terminal: \(error)") }
        do { try temporaryHidingRetainsSuccessfulHint(request) } catch { failures.append("hide: \(error)") }
        let after = try Data(contentsOf: source)
        try check(after == bytes, "Source content changed")
        if !failures.isEmpty { throw Failure(message: failures.joined(separator: "; ")) }
        print("Passed 3 deterministic preview-controller rearm checks (offscreen; no signed Finder proof).")
    }
    private static func failedStartIsNotRemembered(_ source: PreviewViewController.LiveSource) throws {
        let controller = PreviewViewController()
        controller.loadViewIfNeeded()
        defer { controller.viewWillDisappear() }
        var starts = 0
        controller.startWatching = { _, _ in starts += 1; return false }
        controller.beginLiveReload(source)
        controller.viewDidAppear()
        try check(starts == 1, "A failed start left a visibility rearm hint")
        controller.beginLiveReload(source)
        try check(starts == 2, "Explicit new request did not attempt watching")
    }
    private static func terminalReloadIsNotRemembered(_ source: PreviewViewController.LiveSource) throws {
        for result in [LiveReloadResult.preview(.unavailable(.unavailableContent), .defaults), .result(.init(outcome: .unavailable(.unavailableContent)), .defaults), .settingsUnavailable, .disabled] {
            let controller = PreviewViewController()
            controller.loadViewIfNeeded()
            defer { controller.viewWillDisappear() }
            var starts = 0
            var active: PreviewLiveReloader?
            controller.startWatching = { reloader, url in starts += 1; active = reloader; return reloader.start(watching: url) }
            controller.beginLiveReload(source)
            try check(active?.isWatching == true, "The owned file did not start monitoring")
            active?.stop() // Mirrors the reloader's tested release-before-apply boundary.
            controller.applyReload(result)
            controller.viewWillDisappear(); controller.viewDidAppear()
            try check(starts == 1, "A terminal reload retained a visibility rearm hint")
        }
    }
    private static func temporaryHidingRetainsSuccessfulHint(_ source: PreviewViewController.LiveSource) throws {
        let controller = PreviewViewController()
        controller.loadViewIfNeeded()
        defer { controller.viewWillDisappear() }
        var starts = 0
        controller.startWatching = { reloader, url in starts += 1; return reloader.start(watching: url) }
        controller.beginLiveReload(source)
        controller.viewWillDisappear(); controller.viewDidAppear()
        try check(starts == 2, "Temporary hiding lost an eligible successful watch")
    }
}
