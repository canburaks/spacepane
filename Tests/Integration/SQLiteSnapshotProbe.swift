import Foundation
import PreviewContracts
import PreviewCore

/// Used only by the Python test runner with a synthetic temporary file held by
/// another process. POSIX record locks are process-scoped, so a same-process unit
/// test would not establish the writer-conflict boundary.
@main struct SQLiteSnapshotProbe {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw CocoaError(.fileReadInvalidFileName) }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        var context = RequestContext(budget: .standard)
        context.sourceReadPolicy = .sqliteSnapshot
        let shouldBeReadable = CommandLine.arguments[2] == "readable"
        do {
            let bytes = try BoundedFileReader().read(url: url, context: context)
            guard shouldBeReadable, bytes.data == Data(repeating: 7, count: 100) else { throw CocoaError(.fileReadUnknown) }
        } catch PreviewFailure.unavailableContent {
            guard !shouldBeReadable else { throw CocoaError(.fileReadUnknown) }
        }
    }
}
