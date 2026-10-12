import Foundation
import PreviewContracts
import PreviewCore
import PreviewPreferences

/// The result of one thumbnail request. `generic` means the host draws the content-free glyph.
public enum ThumbnailOutcome: Sendable {
    case content(ThumbnailScene)
    case generic(ThumbnailFallbackReason)
}

/// Supplies the shared preferences snapshot. The loader is injected so hosts decide where it lives
/// and tests need no App Group.
public struct ThumbnailPreferencesSource: Sendable {
    private let loader: @Sendable () async -> PreviewPreferencesSnapshot?

    public init(_ loader: @escaping @Sendable () async -> PreviewPreferencesSnapshot?) {
        self.loader = loader
    }

    public func load() async -> PreviewPreferencesSnapshot? { await loader() }

    public static func fixed(_ snapshot: PreviewPreferencesSnapshot?) -> ThumbnailPreferencesSource {
        ThumbnailPreferencesSource { snapshot }
    }

    /// Reads the companion's versioned snapshot. A missing document means first run and yields the
    /// defaults; a corrupt, unreadable or newer-schema document, or no App Group container, yields
    /// nil so thumbnails never guess at the user's choices.
    public static func appGroup(snapshotURL: URL?) -> ThumbnailPreferencesSource {
        guard let snapshotURL else { return ThumbnailPreferencesSource { nil } }
        return ThumbnailPreferencesSource {
            let loaded = await PreferenceStore(url: snapshotURL).load()
            switch loaded.state {
            case .corrupt, .unreadable, .unsupportedVersion: return nil
            case .defaults, .loaded, .migrated: return loaded.snapshot
            }
        }
    }
}

/// Produces a bounded, concealed rendering of a document, or says why it falls back to the glyph.
/// Policy runs first: a disabled, unsupported or content-free type never reaches an adapter.
public struct ContentThumbnailService: Sendable {
    private let registrations: [AdapterRegistration]
    private let reader: any PreviewFileReading
    private let privacy: any PreviewPrivacyFiltering
    private let preferences: ThumbnailPreferencesSource
    private let catalog: FormatCatalog
    private let limits: ThumbnailLimits
    private let admission: ThumbnailAdmission

    /// `admission` bounds how many requests read and parse at once. Copies of the service share it, and so does
    /// a host that keeps one service for every request; a service built without one gets its own.
    public init(registrations: [AdapterRegistration], preferences: ThumbnailPreferencesSource,
                reader: any PreviewFileReading = BoundedFileReader(),
                privacy: any PreviewPrivacyFiltering = DefaultPrivacyFilter(),
                catalog: FormatCatalog = .standard, limits: ThumbnailLimits = .standard,
                admission: ThumbnailAdmission = ThumbnailAdmission()) {
        self.registrations = registrations
        self.preferences = preferences
        self.reader = reader
        self.privacy = privacy
        self.catalog = catalog
        self.limits = limits
        self.admission = admission
    }

    /// The longest a request may take. A host that answers Quick Look arms its reply gate with it.
    public var hardTimeout: Duration { limits.hardTimeout }

    /// The type badge for the file at `url`, from the catalog suffix its name matches. It reads the name only and
    /// does not depend on the outcome, so every reply to the request can carry it, a timeout's included.
    public func badge(for url: URL) -> ThumbnailBadge? {
        ThumbnailBadge.matching(url: url, catalog: catalog)
    }

    /// The outcome and the badge for one request, without a deadline of its own: the host's reply gate bounds
    /// the time and cancels the task. Requests that will read the file wait their turn in the admission.
    public func result(for url: URL, geometry: ThumbnailGeometry) async -> ThumbnailResult {
        let typeBadge = badge(for: url)
        let drawn = await produce(url: url, geometry: geometry)
        return ThumbnailResult(outcome: drawn, badge: typeBadge)
    }

    /// The outcome with a deadline of its own, a Swift-task timer on the cooperative pool. A host that must answer
    /// while that pool is occupied uses `result(for:geometry:)` behind a `ThumbnailReplyGate`, whose timer is not.
    public func outcome(for url: URL, geometry: ThumbnailGeometry) async -> ThumbnailOutcome {
        let service = self
        return await ThumbnailRace.run(limit: limits.hardTimeout, onTimeout: .generic(.timedOut),
                                       onCancel: .generic(.cancelled)) {
            await service.produce(url: url, geometry: geometry)
        }
    }

    private func produce(url: URL, geometry: ThumbnailGeometry) async -> ThumbnailOutcome {
        let snapshot = await preferences.load()
        if Task.isCancelled { return .generic(.cancelled) }
        if let reason = ThumbnailPolicyEvaluator.preflight(preferences: snapshot) { return .generic(reason) }
        guard let snapshot else { return .generic(.settingsUnavailable) }
        // One pipeline, and so one serial worker, per request: concurrent requests do not queue
        // behind each other's parsing and consume their own hard timeout while waiting.
        let pipeline = PreviewPipeline(catalog: catalog, registrations: registrations, reader: reader, privacy: privacy)
        let inspection = await pipeline.inspect(url: url, preferences: snapshot)
        let format: FormatID
        switch ThumbnailPolicyEvaluator.resolve(inspection, catalog: catalog) {
        case .fallback(let reason): return .generic(reason)
        case .draw(let resolved): format = resolved
        }
        if Task.isCancelled { return .generic(.cancelled) }
        // Only a request that is about to read the file waits for a turn; every decision above has answered
        // without one. The wait counts against the caller's deadline, and a cancelled request leaves the queue.
        return await admission.run(ifCancelled: .generic(.cancelled)) {
            await draw(url: url, format: format, snapshot: snapshot, geometry: geometry, pipeline: pipeline)
        }
    }

    private func draw(url: URL, format: FormatID, snapshot: PreviewPreferencesSnapshot, geometry: ThumbnailGeometry,
                      pipeline: PreviewPipeline) async -> ThumbnailOutcome {
        let outcome = await pipeline.preview(url: url, preferences: snapshot, budget: limits.budget(for: format))
        switch outcome {
        case .cancelled: return .generic(.cancelled)
        case .disabledByUser: return .generic(.disabledByUser)
        case .geometryReady: return .generic(.genericPolicy)
        case .unavailable(let failure): return .generic(failure == .deadlineExceeded ? .timedOut : .unavailable)
        case .ready(let presentation):
            // The names decide withholding only: they go to the secret-shape check and to nothing that draws.
            return scene(for: presentation, format: format, snapshot: snapshot, geometry: geometry,
                         fileName: url.lastPathComponent, parentFolderName: url.deletingLastPathComponent().lastPathComponent)
        }
    }

    private func scene(for presentation: TextPresentation, format: FormatID, snapshot: PreviewPreferencesSnapshot,
                       geometry: ThumbnailGeometry, fileName: String, parentFolderName: String?) -> ThumbnailOutcome {
        guard presentation.formatID == format else { return .generic(.nothingToDraw) }
        // A document in which values were concealed is withheld whole, including its pictures.
        guard presentation.redactionCount <= limits.maximumConcealedValues else { return .generic(.withheldConcealedContent) }
        // So is a document whose concealed text or file name still looks credential-bearing: the filter's recall
        // is finite and a thumbnail outlives it in a durable cache (decision 027, D14). This runs before
        // anything is drawn, pictures included, and covers a summary's text as well as a document's own.
        if limits.withholdsSecretShapes,
           ThumbnailSecretShape.mayHoldSecret(presentation.text[...], fileName: fileName, parentFolderName: parentFolderName) {
            return .generic(.withheldSecretShape)
        }
        let metrics = ThumbnailMetrics(geometry: geometry)
        let usesColor = snapshot.syntaxStyle.usesColor
        if let grid = ThumbnailGridBuilder.grid(for: presentation, metrics: metrics) {
            return .content(ThumbnailScene(content: .grid(grid), metrics: metrics, usesColor: usesColor))
        }
        // A notebook is drawn from its cells, not from the figures its code cells saved (`ThumbnailPicturePolicy`).
        let pictures = limits.picturePolicy.allowsPictures(for: format) ? presentation.images : []
        for image in ThumbnailImageSelection.candidates(from: pictures) {
            if Task.isCancelled { return .generic(.cancelled) }
            if let decoded = ThumbnailImageDecoder.decode(image, maximumPixelExtent: geometry.maximumPixelExtent, limits: limits) {
                let picture = ThumbnailPicture(image: decoded, role: image.role)
                return .content(ThumbnailScene(content: .picture(picture), metrics: metrics, usesColor: usesColor))
            }
        }
        // App-made summary text (archive listings, data and database descriptions, package facts) is never
        // drawn: it is not the document's own text and its English schema keys are not localized. Only the
        // document's pictures, tried above, may stand for such a file (decision 027, Q-10).
        if presentation.origin == .summary { return .generic(.summaryText) }
        guard let content = ThumbnailContentBuilder.textContent(for: presentation, metrics: metrics) else {
            return .generic(.nothingToDraw)
        }
        return .content(ThumbnailScene(content: content, metrics: metrics, usesColor: usesColor))
    }
}
