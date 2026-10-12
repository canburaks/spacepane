import Foundation
import Darwin
import UniformTypeIdentifiers
import PreviewContracts
import PreviewFileAccess

// Only the optional type lookup is replaceable; path metadata stays concrete and read-only.
protocol PreviewContentTypeReading: Sendable {
    func contentType(for url: URL) throws -> UTType?
}

private struct FoundationPreviewContentTypes: PreviewContentTypeReading {
    func contentType(for url: URL) throws -> UTType? {
        try url.resourceValues(forKeys: [.contentTypeKey]).contentType
    }
}

struct PreviewFileClassifier: Sendable {
    let access: BoundedReadAccess
    let contentTypes: any PreviewContentTypeReading
    init() { access = BoundedReadAccess(); contentTypes = FoundationPreviewContentTypes() }
    init(access: BoundedReadAccess, contentTypes: any PreviewContentTypeReading) {
        self.access = access; self.contentTypes = contentTypes
    }

    func classify(_ url: URL, catalog: FormatCatalog) throws -> FormatID? {
        // Name recognition is a type/policy decision, not an availability guarantee.
        if let format = catalog.classify(url: url) { return format }
        guard url.isFileURL else { return nil }
        return try access.policy.withoutMaterializing {
            try validateMetadata(url, at: .preflight)
            let type: UTType?
            do { type = try contentTypes.contentType(for: url) }
            catch {
                if let failure = materializationFailure(error) { throw failure }
                type = nil // Retain optional lookup fallback for ordinary metadata errors.
            }
            try validateMetadata(url, at: .finalRead)
            return catalog.classify(url: url, contentType: type)
        }
    }

    private func validateMetadata(_ url: URL, at check: BoundedReadMetadataCheck) throws {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return BoundedReadCall(value: -1, error: EINVAL) }
            return access.call(.metadata(check)) { Int(lstat(path, &info)) }
        }
        guard result.value == 0 else {
            throw access.mappedFailure(result.error,
                fallback: result.error == ENOENT ? .missingFile : .unreadableFile)
        }
        try DatalessFiles.requireMaterialized(flags: access.probe.flags(info.st_flags, at: check))
        let kind = info.st_mode & S_IFMT
        // Directories need type metadata for folder/package routing; never follow a symlink.
        guard kind == S_IFREG || kind == S_IFDIR else { throw PreviewFailure.notRegularFile }
    }

    private func materializationFailure(_ error: any Error) -> PreviewFailure? {
        if let failure = error as? PreviewFailure { return failure }
        var current = error as NSError
        // Foundation may wrap a POSIX refusal. Bound malformed/deep chains and fail closed.
        for _ in 0..<8 {
            if current.domain == NSPOSIXErrorDomain, let code = Int32(exactly: current.code),
               let failure = DatalessFiles.materializationFailure(forPOSIXError: code) { return failure }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { return nil }
            current = underlying
        }
        return .unavailableContent
    }
}
