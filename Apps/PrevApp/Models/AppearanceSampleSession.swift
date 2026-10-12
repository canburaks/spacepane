import Foundation
import Observation
import PreviewContracts
import PreviewCore

/// Owns the Theme page's sample: which format is shown, its one request and its
/// temporary files. Appearance edits restyle the kept result; only choosing another
/// format starts a new request.
@MainActor @Observable
final class AppearanceSampleSession {
    private(set) var selected: FormatID
    private(set) var result: PreviewResult?
    var outcome: PreviewOutcome? { result?.outcome }
    private(set) var generation = UUID()
    private(set) var isLoading = false
    /// The sample's file or folder name; a technical name, never localized.
    private(set) var itemName: String?
    @ObservationIgnored private let pipeline: PreviewPipeline
    @ObservationIgnored private let library: AppearanceSampleLibrary
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var request = UUID()

    init(pipeline: PreviewPipeline, library: AppearanceSampleLibrary = AppearanceSampleLibrary(),
         initial: FormatID = .json, temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.pipeline = pipeline
        self.library = library
        selected = initial
        directory = temporaryDirectory.appendingPathComponent("appearance-samples-\(UUID().uuidString)", isDirectory: true)
    }

    isolated deinit {
        task?.cancel()
        try? FileManager.default.removeItem(at: directory)
    }

    /// Loads the selected sample once; later visits keep the result.
    func loadIfNeeded() {
        if outcome == nil, !isLoading { select(selected) }
    }

    func select(_ id: FormatID) {
        task?.cancel()
        selected = id
        isLoading = true
        let token = UUID()
        request = token
        // App-authored samples are shown whatever the user chose for real files of this type;
        // the choice still governs every user file in the preview and thumbnail hosts.
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(true, for: id)
        task = Task { [weak self, library, pipeline, directory] in
            let result: PreviewResult
            var name: String?
            do {
                let url = try await library.materialize(id, in: directory)
                name = url.lastPathComponent
                result = await pipeline.previewResult(url: url, preferences: preferences)
            } catch {
                result = PreviewResult(outcome: .unavailable(.unavailableContent))
            }
            // A newer selection owns the visible sample; a late result is dropped.
            guard let self, !Task.isCancelled, request == token else { return }
            self.result = result
            itemName = name
            generation = UUID()
            isLoading = false
            task = nil
        }
    }

    /// Cancels the request and removes the temporary sample files.
    func close() {
        task?.cancel()
        task = nil
        request = UUID()
        result = nil
        itemName = nil
        isLoading = false
        try? FileManager.default.removeItem(at: directory)
    }
}
