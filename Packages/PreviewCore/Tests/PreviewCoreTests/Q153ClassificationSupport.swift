import Foundation
import Darwin
import UniformTypeIdentifiers
import Synchronization
import PreviewContracts
@testable import PreviewCore

enum Q153TypeResult: Sendable {
    case type(UTType?), posix(Int32), wrappedPOSIX(Int32), ordinary, deepChain
}
final class Q153ContentTypes: PreviewContentTypeReading, Sendable {
    struct State { var calls = 0, outsideScopes = 0 }
    private let state = Mutex(State())
    let probe: Q153ReadProbe
    let result: Q153TypeResult
    init(_ result: Q153TypeResult = .type(.text), probe: Q153ReadProbe) { self.result = result; self.probe = probe }
    func contentType(for url: URL) throws -> UTType? {
        let depth = probe.snapshot.depth
        state.withLock { $0.calls += 1; if depth == 0 { $0.outsideScopes += 1 } }
        switch result {
        case .type(let type): return type
        case .ordinary: throw CocoaError(.fileReadUnknown)
        case .posix(let code):
            if code == EDEADLK { errno = EACCES } // Refusal tests save/restore errno synchronously.
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        case .wrappedPOSIX(let code):
            let cause = NSError(domain: NSPOSIXErrorDomain, code: Int(code))
            if code == EDEADLK { errno = EACCES }
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadUnknown.rawValue,
                          userInfo: [NSUnderlyingErrorKey: cause])
        case .deepChain:
            var error = NSError(domain: NSPOSIXErrorDomain, code: Int(EDEADLK))
            for _ in 0..<9 {
                error = NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadUnknown.rawValue,
                                userInfo: [NSUnderlyingErrorKey: error])
            }
            throw error
        }
    }
    var snapshot: State { state.withLock { $0 } }
}
final class Q153ClassificationCounts: Sendable {
    struct State { var reads = 0, factories = 0, parses = 0 }
    private let state = Mutex(State())
    func read() { state.withLock { $0.reads += 1 } }
    func factory() { state.withLock { $0.factories += 1 } }
    func parse() { state.withLock { $0.parses += 1 } }
    var snapshot: State { state.withLock { $0 } }
}
private struct Q153ClassificationReader: PreviewFileReading {
    let counts: Q153ClassificationCounts
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        counts.read(); return FileBytes(data: Data("ordinary text".utf8))
    }
}
private struct Q153ClassificationAdapter: FormatAdapter {
    let counts: Q153ClassificationCounts
    func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        counts.parse(); return ParsedTextDocument(text: input.text)
    }
}
let q153ClassificationCatalog = FormatCatalog(descriptors: [
    FormatDescriptor(id: .plainText, contentTypes: [.text], suffixAliases: [], group: .text,
                     thumbnail: .content, nameKey: "test", descriptionKey: "test")
])
func q153ClassificationPipeline(probe: Q153ReadProbe, types: Q153ContentTypes,
                                counts: Q153ClassificationCounts, catalog: FormatCatalog = q153ClassificationCatalog) -> PreviewPipeline {
    PreviewPipeline(catalog: catalog, registrations: [AdapterRegistration(formatID: .plainText) {
        counts.factory(); return Q153ClassificationAdapter(counts: counts)
    }], reader: Q153ClassificationReader(counts: counts),
        classifier: PreviewFileClassifier(access: BoundedReadAccess(policy: probe, probe: probe), contentTypes: types))
}
