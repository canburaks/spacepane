import Foundation
import UniformTypeIdentifiers
import PreviewContracts

public struct PreviewPipeline: Sendable {
    private let catalog: FormatCatalog
    private let classifier: PreviewFileClassifier
    private let worker: PreviewWorker

    /// - Parameter executor: the serial queue this pipeline's blocking reads and parses run on. The default is
    ///   one of its own, so a slow request here never occupies the cooperative thread pool or delays another
    ///   pipeline (decision 027, Q-40). Pass one executor to several pipelines only to make them take turns.
    /// - Parameter stageObserver: opt-in worker execution timing, excluding queue wait. A nil observer does no
    ///   timing or signpost work; events contain only a fixed stage, a monotonic interval and a count of one.
    public init(catalog: FormatCatalog = .standard, registrations: [AdapterRegistration],
                reader: any PreviewFileReading = BoundedFileReader(),
                privacy: any PreviewPrivacyFiltering = DefaultPrivacyFilter(),
                executor: PreviewWorkerExecutor = PreviewWorkerExecutor(),
                stageObserver: PreviewStageObserver? = nil) {
        self.init(catalog: catalog, registrations: registrations, reader: reader, privacy: privacy,
                  executor: executor, stageObserver: stageObserver, classifier: PreviewFileClassifier())
    }

    init(catalog: FormatCatalog = .standard, registrations: [AdapterRegistration],
         reader: any PreviewFileReading = BoundedFileReader(),
         privacy: any PreviewPrivacyFiltering = DefaultPrivacyFilter(),
         executor: PreviewWorkerExecutor = PreviewWorkerExecutor(), stageObserver: PreviewStageObserver? = nil,
         classifier: PreviewFileClassifier) {
        precondition(Set(registrations.map(\.formatID)).count == registrations.count)
        self.catalog = catalog
        self.classifier = classifier
        worker = PreviewWorker(catalog: catalog, registrations: registrations, reader: reader, privacy: privacy,
                               executor: executor, stageObserver: stageObserver, classifier: classifier)
    }

    @concurrent public func inspect(url: URL, preferences: PreviewPreferencesSnapshot = .defaults) async -> PreviewInspection {
        do {
            guard let format = try classifier.classify(url, catalog: catalog) else { return .unsupported }
            return preferences.isEnabled(format, catalog: catalog) ? .enabled(format) : .disabledByUser(format)
        } catch let failure as PreviewFailure {
            return .unavailable(failure)
        } catch {
            return .unavailable(.unreadableFile)
        }
    }

    /// Runs blocking reads and parsing on the pipeline's own serial executor, never on inherited UI isolation
    /// and never on a cooperative-pool thread.
    /// Cancellation/deadlines are cooperative checkpoints; native filesystem calls cannot be preempted.
    @concurrent public func preview(url: URL, preferences: PreviewPreferencesSnapshot = .defaults,
                                    budget: PreviewBudget? = nil) async -> PreviewOutcome {
        await previewResult(url: url, preferences: preferences, budget: budget).outcome
    }

    /// Carries the effective limits through successes and failures without another classification or read.
    @concurrent public func previewResult(url: URL, preferences: PreviewPreferencesSnapshot = .defaults,
                                         budget: PreviewBudget? = nil) async -> PreviewResult {
        await worker.previewResult(url: url, preferences: preferences, budget: budget)
    }
}

/// One pipeline owns one serial parsing worker. Copies share that worker; hosts should
/// retain their pipeline between requests. Queued cancelled requests check cancellation
/// before file access. This bounds simultaneous blocking work without blocking waiters.
/// The worker's isolation is the pipeline's `PreviewWorkerExecutor`, a dispatch serial queue, so a
/// read or parse that blocks holds a thread of that queue, not one of the cooperative pool.
private actor PreviewWorker {
    let catalog: FormatCatalog
    let registrations: [AdapterRegistration]
    let reader: any PreviewFileReading
    let privacy: any PreviewPrivacyFiltering
    private let classifier: PreviewFileClassifier
    /// Kept alive here: the unowned executor below does not retain it.
    private let executor: PreviewWorkerExecutor
    private let stageObserver: PreviewStageObserver?

    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }

    init(catalog: FormatCatalog, registrations: [AdapterRegistration], reader: any PreviewFileReading,
         privacy: any PreviewPrivacyFiltering, executor: PreviewWorkerExecutor, stageObserver: PreviewStageObserver?,
         classifier: PreviewFileClassifier) {
        self.catalog = catalog
        self.registrations = registrations
        self.reader = reader
        self.privacy = privacy
        self.executor = executor
        self.stageObserver = stageObserver
        self.classifier = classifier
    }

    func previewResult(url: URL, preferences: PreviewPreferencesSnapshot, budget requestedBudget: PreviewBudget?) -> PreviewResult {
        let interval = stageObserver?.begin(.pipeline)
        defer { interval?.finish() }
        var effectiveBudget: PreviewBudget?
        let outcome: PreviewOutcome = {
            if let requestedBudget, !requestedBudget.isValid { return .unavailable(.invalidBudget) }
            do {
                try Task.checkCancellation()
                guard let formatID = try classifier.classify(url, catalog: catalog) else { return .unavailable(.unsupportedFormat) }
                // Keep disabled registrations in classification. No reads or factories occur past this gate.
                guard preferences.isEnabled(formatID, catalog: catalog) else { return .disabledByUser(formatID) }
                guard let registration = registrations.first(where: { $0.formatID == formatID }) else {
                    return .unavailable(.unsupportedFormat)
                }
                let budget = requestedBudget ?? registration.defaultBudget ?? .standard
                guard budget.isValid else { return .unavailable(.invalidBudget) }
                effectiveBudget = budget
                var context = RequestContext(budget: budget)
                context.sourceReadPolicy = registration.sourcePolicy
                context.nameHint = PreviewNameHint(url: url)
                context.options = preferences.requestOptions
                let document: ParsedTextDocument
                let byteCount: Int
                let encoding: TextEncoding
                var truncatedSourceBytes: Int?
                var sourceSize: PresentationFacts.Fact?
                switch registration.inputPath {
                case .geometry(let factory):
                    let bytes = try reader.read(url: url, context: context)
                    guard bytes.data.count <= budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
                    let mesh = try factory().parse(bytes, context: context)
                    guard mesh.outputByteCount <= budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
                    try context.checkpoint()
                    return .geometryReady(GeometryPresentation(formatID: formatID, mesh: mesh, byteCount: bytes.data.count,
                        facts: PresentationFacts(sizeFact(read: bytes.data.count, total: bytes.totalByteCount).map { [$0] } ?? [])))
                case .text(let factory):
                    let adapter = factory()
                    // Strict unless the adapter itself declares that it can show a leading prefix of an
                    // oversized file or reformat over-long lines; registrations and hosts stay unchanged.
                    let policy = (adapter as? any TextInputPolicyProviding)?.textInputPolicy ?? .strict
                    let (bytes, totalSourceBytes) = try readText(url: url, policy: policy, context: context)
                    guard bytes.data.count <= budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
                    let decoded = try TextDecoder.decode(bytes, context: context, enforcesLineLength: !policy.allowsLongLines)
                    byteCount = decoded.byteCount
                    encoding = decoded.encoding
                    truncatedSourceBytes = totalSourceBytes
                    sourceSize = sizeFact(read: bytes.data.count, total: totalSourceBytes ?? bytes.totalByteCount)
                    if bytes.data.isEmpty, bytes.totalByteCount == 0, registration.emptyInputPolicy == .emptyPreview {
                        document = ParsedTextDocument(text: "")
                    } else {
                        document = try adapter.parse(decoded, context: context)
                    }
                case .binary(let factory):
                    let bytes = try reader.read(url: url, context: context)
                    guard bytes.data.count <= budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
                    byteCount = bytes.data.count
                    sourceSize = sizeFact(read: bytes.data.count, total: bytes.totalByteCount)
                    if bytes.data.isEmpty, bytes.totalByteCount == 0, registration.emptyInputPolicy == .emptyPreview {
                        document = ParsedTextDocument(text: "")
                    } else {
                        document = try factory().parse(bytes, context: context)
                    }
                    encoding = document.decodedEncoding ?? .utf8
                case .url(let factory):
                    byteCount = 0
                    encoding = .utf8
                    document = try factory().parse(url: url, context: context)
                case .randomAccess(let factory):
                    let source = try reader.openRandomAccess(url: url, context: context)
                    byteCount = Int(clamping: source.byteCount)
                    if source.byteCount >= 0 { sourceSize = .size(source.byteCount) }
                    encoding = .utf8
                    document = try factory().parse(source, context: context)
                }
                let safe = try privacy.filter(document, context: context)
                try context.checkpoint()
                let lineCount = try TextMetrics.validate(safe.text, context: context)
                // Hidden-content scan of the concealed text, so its lines match the gutter and a concealed
                // secret is never examined. Only text the file itself holds is scanned.
                let hiddenContent = HiddenContentScanner.appliesTo(registration.inputPath, document: document)
                    ? try HiddenContentScanner.scan(text: safe.text, formatID: formatID, fileName: url.lastPathComponent,
                                                    privacy: privacy, context: context)
                    : []
                let images = document.images.filter(\.isValid)
                return .ready(TextPresentation(formatID: formatID, text: safe.text, lineCount: lineCount,
                    byteCount: byteCount, encoding: encoding, redactionCount: safe.redactionCount,
                    syntax: safe.syntax, midi: document.midi, invalidRecordLines: document.invalidRecordLines,
                    sourceRecordCount: document.sourceRecordCount, sourceLanguage: document.sourceLanguage,
                    images: images, truncatedSourceBytes: truncatedSourceBytes, isReformatted: document.isReformatted,
                    findings: PreviewFindings.normalized(
                        document.findings + safe.findings + hiddenContent
                            + syncFolderFindings(url: url, redactionCount: safe.redactionCount)),
                    origin: document.origin, facts: facts(for: document, sourceSize: sourceSize)))
            } catch is CancellationError { return .cancelled }
            catch let failure as PreviewFailure { return .unavailable(failure) }
            catch { return .unavailable(.unreadableFile) }
        }()
        return PreviewResult(outcome: outcome, effectiveBudget: effectiveBudget)
    }

    /// Source metadata already acquired by the selected reader. Never infer a directory size from zero.
    private func sizeFact(read: Int, total: Int?) -> PresentationFacts.Fact? {
        guard read >= 0 else { return nil }
        guard let total else { return .size(Int64(read)) }
        guard total >= read else { return nil }
        return total > read ? .shownSize(shown: Int64(read), total: Int64(total)) : .size(Int64(read))
    }

    private func facts(for document: ParsedTextDocument, sourceSize: PresentationFacts.Fact?) -> PresentationFacts {
        // Source text already has trustworthy byte/encoding provenance. Non-text renderers must consume typed
        // facts instead of interpreting the legacy byteCount field; parser-supplied facts keep their priority.
        guard document.origin == .summary || document.origin == .converted, let sourceSize else { return document.facts }
        guard !document.facts.facts.contains(where: {
            switch $0 { case .size, .shownSize: true; default: false }
        }) else { return document.facts }
        return PresentationFacts(document.facts.facts + [sourceSize])
    }

    /// A complete read, or for an adapter that accepts it the leading complete records of an oversized
    /// file with the whole file's size. Readers without the leading-bytes capability stay strict.
    private func readText(url: URL, policy: TextInputPolicy, context: RequestContext) throws -> (FileBytes, Int?) {
        guard let boundary = policy.partialBoundary, let leading = reader as? any LeadingBytesReading else {
            return (try reader.read(url: url, context: context), nil)
        }
        let bytes = try leading.readLeading(url: url, context: context)
        guard let total = bytes.totalByteCount, total > bytes.data.count else { return (bytes, nil) }
        let kept = try PartialTextPrefix.keptByteCount(of: bytes.data, boundary: boundary,
                                                       budget: context.budget, context: context)
        return (FileBytes(data: Data(bytes.data.prefix(kept))), total)
    }
}

/// Secrets concealed from a file in a synced folder may already be copied to other devices or servers.
/// Only text previews that concealed something get the warning. It is a path test with no file access,
/// and only the provider is reported, never the folder name (which can contain an account address).
private func syncFolderFindings(url: URL, redactionCount: Int) -> [PreviewFinding] {
    guard redactionCount > 0, let provider = SyncFolderLocation.provider(for: url) else { return [] }
    return [PreviewFinding(kind: .secretSyncedFolder, count: 1, detail: .syncProvider(provider))]
}
