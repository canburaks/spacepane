import Foundation
import Observation
import PreviewRenderers

/// Owns one on-demand scan of installed apps for overlapping Quick Look extensions. The result describes
/// declared types only; nothing here states which provider Finder uses. A late result from a cancelled or
/// replaced scan is dropped, and no scan runs until the user asks for one.
@MainActor @Observable
final class QuickLookProviderDiagnostics {
    enum State: Equatable {
        case idle
        case scanning
        case finished(QuickLookProviderReport)
    }

    private(set) var state = State.idle
    @ObservationIgnored private let scan: @Sendable () async throws -> QuickLookProviderReport
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var request = UUID()

    init(scan: @escaping @Sendable () async throws -> QuickLookProviderReport) {
        self.scan = scan
    }

    convenience init(scanner: QuickLookProviderScanner) {
        self.init(scan: { try await scanner.scan() })
    }

    isolated deinit { task?.cancel() }

    var isScanning: Bool { state == .scanning }

    /// Starts a scan, replacing one that is still running. The file access runs in the scanner's actor.
    func startScan() {
        task?.cancel()
        let token = UUID()
        request = token
        state = .scanning
        let scan = scan
        task = Task { [weak self] in
            let report = try? await scan()
            guard let self, !Task.isCancelled, request == token else { return }
            // A failed or cancelled scan leaves nothing to show and returns to the starting state.
            state = report.map(State.finished) ?? .idle
            task = nil
        }
    }

    /// Stops a running scan and forgets any partial result.
    func cancel() {
        task?.cancel()
        task = nil
        request = UUID()
        if state == .scanning { state = .idle }
    }
}

extension QuickLookProviderReport {
    /// What VoiceOver hears when a scan ends: the conclusion the results list opens with, in the same words.
    func announcement(locale: Locale = .current, languagePreferences: [String]? = nil) -> String {
        guard !providers.isEmpty else {
            return PreviewStrings.text(.providersNone, languagePreferences: languagePreferences)
        }
        return PreviewStrings.format(.providersFound, arguments: [providers.count], locale: locale,
                                     languagePreferences: languagePreferences)
    }
}
