import CoreGraphics
import QuickLookThumbnailing
import PreviewCore
import PreviewFileAccess
import PreviewFormats
import PreviewPreferences
import PreviewRenderers
import PreviewThumbnails

/// Draws a bounded, concealed rendering of the document when the catalog, the user's file-type
/// choice and the content-thumbnail switch all allow it, and the content-free glyph otherwise.
/// A thumbnail never draws a file name, a path or unconcealed text. The system keeps thumbnails in
/// a durable cache, so an earlier image can outlive a later change of these choices.
final class ThumbnailProvider: QLThumbnailProvider {
    /// Registrations are the composition boundary. Policy is evaluated before any adapter is built.
    private static let service = ContentThumbnailService(
        registrations: StandardFormatAdapters.registrations,
        preferences: .appGroup(snapshotURL: PreferencesLocation.appGroupSnapshotURL(
            identifier: HostedConfiguration().appGroupIdentifier)))

    /// The deadline timer is a Dispatch timer, which needs no thread of the Swift pool that parsing occupies.
    private static let scheduler = DispatchThumbnailScheduler()

    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        // Fail closed before constructing the service or reading request/source metadata.
        let fileAccessAllowed = (try? DatalessFiles.refuseMaterializationForProcess()) != nil
        let hostGeometry = PreviewHostGeometry(width: request.maximumSize.width, height: request.maximumSize.height)
        let trace = PreviewHostTrace(surface: .thumbnail, geometry: hostGeometry)
        guard let geometry = ThumbnailGeometry(maximumSize: request.maximumSize, scale: request.scale) else {
            trace.finish(.invalidGeometry)
            handler(nil, CocoaError(.coderInvalidValue))
            return
        }
        guard fileAccessAllowed else {
            trace.finish(.unavailable, geometry: hostGeometry)
            handler(Self.reply(for: ThumbnailResult(outcome: .generic(.unavailable), badge: nil), size: geometry.size), nil)
            return
        }
        let completion = Completion(handler: handler)
        let url = request.fileURL
        let service = Self.service
        let size = geometry.size
        // The gate answers Quick Look exactly once: with the work's result, or with the glyph when the deadline
        // comes first. The deadline is a Dispatch timer, so it fires even while every cooperative thread is busy
        // parsing. Parsing, decoding and layout finish before the reply exists; its drawing block only paints.
        let gate = ThumbnailReplyGate<ThumbnailResult>(
            limit: service.hardTimeout, scheduler: Self.scheduler,
            timeoutValue: ThumbnailResult(outcome: .generic(.timedOut), badge: service.badge(for: url)),
            deliver: { result in
                let outcome = Self.diagnosticOutcome(result)
                // A completed policy decision used a validated snapshot; a timeout/cancel does not prove
                // that settings loading finished. Availability does not claim loaded versus defaults.
                if outcome == .settingsUnavailable { trace.settings(.unavailable) }
                else if outcome != .timedOut && outcome != .cancelled { trace.settings(.available) }
                trace.finish(outcome, geometry: hostGeometry)
                completion.handler(Self.reply(for: result, size: size), nil)
            })
        gate.start { await service.result(for: url, geometry: geometry) }
    }

    private static func diagnosticOutcome(_ result: ThumbnailResult) -> PreviewHostOutcome {
        switch result.outcome {
        case .content: .ready
        case .generic(.timedOut): .timedOut
        case .generic(.cancelled): .cancelled
        case .generic(.disabledByUser): .disabled
        case .generic(.settingsUnavailable): .settingsUnavailable
        case .generic(.unavailable): .unavailable
        case .generic: .glyph
        }
    }

    private static func reply(for result: ThumbnailResult, size: CGSize) -> QLThumbnailReply {
        let built: QLThumbnailReply
        switch result.outcome {
        case .content(let scene):
            built = QLThumbnailReply(contextSize: size) { context in
                ThumbnailRenderer.draw(scene, in: context)
                return true
            }
        case .generic:
            built = QLThumbnailReply(contextSize: size) { context in
                ThumbnailRenderer.drawGlyph(in: context, size: size)
                return true
            }
        }
        applyBadge(result.badge, to: built)
        return built
    }

    /// The one place the type badge is set. `QLThumbnailReply.extensionBadge` (macOS 12 and later) is new to this
    /// repository, so it stays behind this wrapper. The token is the catalog suffix the request matched, never a part
    /// of the file's name; every reply carries it, the glyph for a timeout or a withheld document included.
    private static func applyBadge(_ badge: ThumbnailBadge?, to reply: QLThumbnailReply) {
        // `extensionBadge` is a non-optional String; an empty badge draws nothing.
        reply.extensionBadge = badge?.token ?? ""
    }
}

/// Carries Quick Look's completion handler into the reply gate, which answers the request.
/// Invariant: the gate calls the handler exactly once and nothing else retains or calls it. Quick Look
/// documents that the handler may be called asynchronously, from any thread, after the method returns.
private struct Completion: @unchecked Sendable {
    let handler: (QLThumbnailReply?, Error?) -> Void
}
