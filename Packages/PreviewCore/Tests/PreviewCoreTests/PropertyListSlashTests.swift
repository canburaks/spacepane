import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

/// Tier 1 quick win 3 (docs/market/2026-10-14-quick-wins-after-safety-lens-3.md): the property-list
/// Source view shows `/` as written, and a URL password in a plist value stays concealed.
@Suite("Property-list slashes and URL credentials")
struct PropertyListSlashTests {
    private func filtered(_ source: String) throws -> SafeText {
        let context = RequestContext(budget: .standard)
        let parsed = try PropertyListSourceAdapter().parse(.init(text: source, encoding: .utf8, byteCount: source.utf8.count),
                                                           context: context)
        return try DefaultPrivacyFilter().filter(parsed, context: context)
    }

    @Test func urlsAndPathsAreShownWithoutEscapedSlashes() throws {
        let result = try filtered("""
        <plist version="1.0"><dict><key>homepage</key><string>https://example.test/docs/index.html</string>\
        <key>path</key><string>/Applications/Example.app</string></dict></plist>
        """)
        #expect(result.text.contains("https://example.test/docs/index.html"))
        #expect(result.text.contains("/Applications/Example.app"))
        #expect(!result.text.contains(#"\/"#))
        #expect(result.redactionCount == 0)
    }

    @Test func aURLPasswordInAPlistValueIsConcealedAndTheHostStaysReadable() throws {
        let result = try filtered("""
        <plist version="1.0"><dict><key>DatabaseURL</key>\
        <string>postgres://app:synthetic-plist-url-password@db.example.test:5432/main</string></dict></plist>
        """)
        let leaked = result.text.contains("synthetic-plist-url-password")
        #expect(!leaked)
        #expect(result.text.contains("@db.example.test:5432/main"))
        #expect(result.redactionCount == 1)
    }

    @Test func binaryPropertyListsShowSlashesAsWritten() throws {
        let input: [String: Any] = ["feed": "https://example.test/a/b"]
        let binary = try PropertyListSerialization.data(fromPropertyList: input, format: .binary, options: 0)
        let parsed = try PropertyListSourceAdapter().parse(FileBytes(data: binary), context: RequestContext(budget: .standard))
        #expect(parsed.text.contains("https://example.test/a/b"))
        #expect(!parsed.text.contains(#"\/"#))
    }
}
