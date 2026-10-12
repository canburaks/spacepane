import Foundation
import Observation
import PreviewContracts
import PreviewPreferences

/// Owns one bounded import request. A result may apply only while this owner is active.
@MainActor @Observable
final class AppearanceThemeTransfer {
    enum Message: Equatable {
        case imported, exported, failed
        case importError(AppearanceThemeError)

        /// A failure the page draws in the caution style; a finished import or export is a quiet note.
        var isProblem: Bool {
            switch self {
            case .imported, .exported: return false
            case .failed, .importError: return true
            }
        }
    }

    private(set) var isReading = false
    private(set) var message: Message?
    /// The last import was read in full but not applied, because the appearance changed while the file was being
    /// read. It is separate from `message`, which stays empty then, so the page can say why nothing happened.
    private(set) var wasSuperseded = false
    @ObservationIgnored private let read: @Sendable (URL) async throws -> PreviewAppearance
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    convenience init() {
        let reader = AppearanceThemeReader()
        self.init(read: { try await reader.read(at: $0) })
    }

    init(read: @escaping @Sendable (URL) async throws -> PreviewAppearance) {
        self.read = read
    }

    isolated deinit { task?.cancel() }

    func clearMessage() {
        message = nil
        wasSuperseded = false
    }

    func prepareExport(_ appearance: PreviewAppearance) -> Data? {
        message = nil
        wasSuperseded = false
        do { return try AppearanceThemeCodec.encode(appearance) }
        catch { message = .failed; return nil }
    }

    func exportCompleted(_ result: Result<URL, any Error>) {
        switch result {
        case .success: message = .exported
        case .failure(let error): reportFailure(error)
        }
    }

    func importCompleted(_ result: Result<URL, any Error>, settings: CompanionSettings) {
        switch result {
        case .success(let url): importTheme(at: url, settings: settings)
        case .failure(let error): reportFailure(error)
        }
    }

    func cancelImport() {
        task?.cancel()
        task = nil
        generation = UUID()
        isReading = false
    }

    private func importTheme(at url: URL, settings: CompanionSettings) {
        cancelImport()
        message = nil
        wasSuperseded = false
        isReading = true
        let requestGeneration = generation
        let appearanceRevision = settings.appearanceRevision
        let read = read
        task = Task { [weak self, weak settings] in
            do {
                let appearance = try await read(url)
                guard let self, !Task.isCancelled, generation == requestGeneration else { return }
                // A more recent appearance edit wins; unrelated file-policy edits remain valid.
                guard let settings else {
                    finishImport()
                    return
                }
                guard settings.appearanceRevision == appearanceRevision else {
                    wasSuperseded = true
                    finishImport()
                    return
                }
                guard appearance.isValid else {
                    message = .importError(.invalidDocument)
                    finishImport()
                    return
                }
                // One undoable step: Undo restores the appearance the import replaced.
                settings.perform(.importTheme) { $0.appearance = appearance }
                message = .imported
                finishImport()
            } catch {
                guard let self, !Task.isCancelled, generation == requestGeneration else { return }
                reportFailure(error)
                finishImport()
            }
        }
    }

    private func finishImport() {
        isReading = false
        task = nil
    }

    private func reportFailure(_ error: any Error) {
        if error is CancellationError || (error as? CocoaError)?.code == .userCancelled { message = nil }
        else if let error = error as? AppearanceThemeError { message = .importError(error) }
        else { message = .failed }
    }
}
