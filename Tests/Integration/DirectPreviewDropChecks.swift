import AppKit
import Synchronization

private struct DropCheckFailure: Error, CustomStringConvertible {
    let description: String
}

private final class DeferredFileURL: NSObject, NSPasteboardItemDataProvider {
    private let readCount = Mutex(0)
    var reads: Int { readCount.withLock { $0 } }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        readCount.withLock { $0 += 1 }
        item.setString("file:///tmp/deferred-drop.json", forType: type)
    }
}

/// Uses private pasteboards; never reads or replaces the user's clipboard.
@main @MainActor
struct DirectPreviewDropChecks {
    static func main() throws {
        try acceptsOneLocalURLWithoutReadingTheFile()
        try rejectsMultipleAndNonFileItems()
        try rejectsMalformedAndNonlocalURLs()
        print("Passed 3 file-drop checks (private pasteboards; no signed drag validation).")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw DropCheckFailure(description: message) }
    }

    private static func withPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        try body(pasteboard)
    }

    private static func acceptsOneLocalURLWithoutReadingTheFile() throws {
        // A nonexistent, Unicode path must still be accepted: no stat/open at ingress.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("δοκιμή file.json")
        try withPasteboard { pasteboard in
            pasteboard.writeObjects([url as NSURL])
            try check(DirectPreviewFileDrop.isCandidate(pasteboard), "One file URL must be a drop candidate")
            try check(DirectPreviewFileDrop.fileURL(from: pasteboard) == url,
                      "Read the native URL without requiring available bytes or rewriting its path")
        }
        try withPasteboard { pasteboard in
            let provider = DeferredFileURL()
            let item = NSPasteboardItem()
            item.setDataProvider(provider, forTypes: [.fileURL])
            pasteboard.writeObjects([item])
            try check(DirectPreviewFileDrop.isCandidate(pasteboard) && provider.reads == 0,
                      "Hover must inspect metadata without requesting deferred URL data")
        }
    }

    private static func rejectsMultipleAndNonFileItems() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("drop-check.json")
        try withPasteboard { pasteboard in
            pasteboard.writeObjects([url as NSURL, url as NSURL])
            try check(!DirectPreviewFileDrop.isCandidate(pasteboard)
                      && DirectPreviewFileDrop.fileURL(from: pasteboard) == nil,
                      "Never choose the first of multiple files")
        }
        try withPasteboard { pasteboard in
            let text = NSPasteboardItem()
            text.setString("unrelated item", forType: .string)
            pasteboard.writeObjects([url as NSURL, text])
            try check(!DirectPreviewFileDrop.isCandidate(pasteboard)
                      && DirectPreviewFileDrop.fileURL(from: pasteboard) == nil,
                      "A file plus another item must not silently discard the extra item")
        }
        try withPasteboard { pasteboard in
            let text = NSPasteboardItem()
            text.setString("unrelated item", forType: .string)
            pasteboard.writeObjects([text])
            try check(!DirectPreviewFileDrop.isCandidate(pasteboard)
                      && DirectPreviewFileDrop.fileURL(from: pasteboard) == nil,
                      "A pasted path or text is not an authorized file URL")
        }
    }

    private static func rejectsMalformedAndNonlocalURLs() throws {
        for value in ["https://example.invalid/file.json", "file://remote.invalid/file.json",
                      "file:relative.json", "not a URL", "file:///tmp/file.json?query=1",
                      "file:///tmp/file.json#fragment"] {
            try withPasteboard { pasteboard in
                let item = NSPasteboardItem()
                item.setString(value, forType: .fileURL)
                pasteboard.writeObjects([item])
                try check(DirectPreviewFileDrop.fileURL(from: pasteboard) == nil,
                          "Reject malformed, nonlocal and ambiguous file URLs")
            }
        }
        try withPasteboard { pasteboard in
            let web = URL(string: "https://example.invalid/file.json")!
            pasteboard.writeObjects([web as NSURL])
            try check(!DirectPreviewFileDrop.isCandidate(pasteboard)
                      && DirectPreviewFileDrop.fileURL(from: pasteboard) == nil,
                      "A normal web-link drop must not start a preview or a download")
        }
    }
}
