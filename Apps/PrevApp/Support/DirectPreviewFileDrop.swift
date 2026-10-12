import AppKit

/// URL-only ingress. File classification, access and reading belong to PreviewSession.
@MainActor
enum DirectPreviewFileDrop {
    static func isCandidate(_ pasteboard: NSPasteboard) -> Bool {
        // Inspect all items before filtering. A file plus an unrelated item is
        // still a multiple-item drop, not permission to silently pick one file.
        guard let items = pasteboard.pasteboardItems, items.count == 1 else { return false }
        return items[0].types.contains(.fileURL)
    }

    static func fileURL(from pasteboard: NSPasteboard) -> URL? {
        guard isCandidate(pasteboard),
              let objects = pasteboard.readObjects(forClasses: [NSURL.self],
                                                   options: [.urlReadingFileURLsOnly: true]),
              objects.count == 1, let url = objects[0] as? URL,
              url.isFileURL, url.path.hasPrefix("/"),
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return nil }
        if let host = url.host, !host.isEmpty, host.lowercased() != "localhost" { return nil }
        // Keep the native NSURL bridge intact: reconstructing a pasted path
        // would discard the system's sandbox grant. Do not stat or load bytes.
        return url
    }
}
