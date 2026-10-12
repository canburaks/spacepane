import Foundation
import Synchronization
import PreviewContracts
@testable import PreviewFormats

final class Q153BundleSignatureProbe: CodeSignatureReader, Sendable {
    private let count = Mutex(0)
    var calls: Int { count.withLock { $0 } }
    func read(url: URL, context: RequestContext) throws -> CodeSignatureReport {
        count.withLock { $0 += 1 }
        return CodeSignatureReport(summary: .unavailable)
    }
}
struct Q153BundleFixture {
    let directory: URL
    let url: URL
    init() throws {
        directory = try PackageTestSupport.temporaryDirectory()
        url = directory.appendingPathComponent("Owned.app", isDirectory: true)
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PackageFixtures.plist(["CFBundleName": "Owned"]).write(to: contents.appendingPathComponent("Info.plist"))
    }
    /// Info.plist plus the icon, nested framework, signature directory and executable the summary requests.
    func addDescendants() throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        let frameworks = contents.appendingPathComponent("Frameworks/Nested.framework", isDirectory: true)
        let signature = contents.appendingPathComponent("_CodeSignature", isDirectory: true)
        let macos = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: signature, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let icon = PackageFixtures.icns([("ic07", PackageFixtures.png(width: 16, height: 16))])
        try icon.write(to: resources.appendingPathComponent("AppIcon.icns"))
        try Data("framework".utf8).write(to: frameworks.appendingPathComponent("Info.plist"))
        try Data("signature".utf8).write(to: signature.appendingPathComponent("CodeResources"))
        try Data("not-macho".utf8).write(to: macos.appendingPathComponent("Owned"))
        try PackageFixtures.plist([
            "CFBundleName": "Owned", "CFBundleIconFile": "AppIcon", "CFBundleExecutable": "Owned",
        ]).write(to: contents.appendingPathComponent("Info.plist"))
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}
