import Darwin
import PreviewFileAccess

/// Runs only in its own disposable executable. No provider file or user preference is touched.
@main
struct DatalessProcessChecks {
    enum Failure: Error { case unexpectedPolicy, expectedBodyFailure }

    static func main() throws {
        let type = Int32(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES)
        let process = Int32(IOPOL_SCOPE_PROCESS), thread = Int32(IOPOL_SCOPE_THREAD)
        let off = Int32(IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        try DatalessFiles.refuseMaterializationForProcess()
        guard getiopolicy_np(type, process) == off else { throw Failure.unexpectedPolicy }
        try DatalessFiles.refuseMaterializationForProcess()
        guard getiopolicy_np(type, process) == off else { throw Failure.unexpectedPolicy }
        let previous = getiopolicy_np(type, thread)
        guard previous >= 0 else { throw Failure.unexpectedPolicy }
        try DatalessFiles.withoutMaterializing {
            guard getiopolicy_np(type, thread) == off else { throw Failure.unexpectedPolicy }
            try DatalessFiles.withoutMaterializing {
                guard getiopolicy_np(type, thread) == off else { throw Failure.unexpectedPolicy }
            }
            guard getiopolicy_np(type, thread) == off else { throw Failure.unexpectedPolicy }
        }
        guard getiopolicy_np(type, thread) == previous else { throw Failure.unexpectedPolicy }
        do {
            try DatalessFiles.withoutMaterializing { throw Failure.expectedBodyFailure }
            throw Failure.unexpectedPolicy
        } catch Failure.expectedBodyFailure {}
        guard getiopolicy_np(type, thread) == previous,
              getiopolicy_np(type, process) == off else { throw Failure.unexpectedPolicy }
        print("Passed real process refusal and nested thread restoration checks (disposable process; no provider/Finder proof).")
    }
}
