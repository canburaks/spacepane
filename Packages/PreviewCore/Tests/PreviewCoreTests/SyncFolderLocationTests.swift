import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

private struct BytesReader: PreviewFileReading {
    let data: Data
    func read(url: URL, context: RequestContext) throws -> FileBytes { FileBytes(data: data) }
}

@Suite("Sync-folder location")
struct SyncFolderLocationTests {
    private func provider(_ path: String) -> PreviewSyncProvider? {
        SyncFolderLocation.provider(for: URL(fileURLWithPath: path, isDirectory: false))
    }

    @Test(arguments: [
        ("/Users/test/Library/Mobile Documents/com~apple~CloudDocs/notes.txt", PreviewSyncProvider.iCloudDrive),
        ("/Users/test/Library/Mobile Documents/iCloud~com~example~app/Documents/a/b/notes.txt", .iCloudDrive),
        ("/Users/test/Library/Mobile Documents/notes.txt", .iCloudDrive),
        ("/Users/test/Library/CloudStorage/Dropbox/notes.txt", .dropbox),
        ("/Users/test/Library/CloudStorage/Dropbox-Personal/Team/notes.txt", .dropbox),
        ("/Users/test/Library/CloudStorage/GoogleDrive-someone@example.com/My Drive/notes.txt", .googleDrive),
        ("/Users/test/Library/CloudStorage/OneDrive-Personal/Documents/notes.txt", .oneDrive),
        ("/Users/test/Library/CloudStorage/OneDrive-Contoso Ltd/notes.txt", .oneDrive),
        ("/Users/test/Library/CloudStorage/Box-Box/notes.txt", .box),
        ("/Users/test/Library/CloudStorage/Box/notes.txt", .box),
        ("/Users/test/Library/CloudStorage/SynologyDrive-nas/notes.txt", .other),
        ("/Users/test/Library/CloudStorage/ProtonDrive-someone@example.com-folder/notes.txt", .other),
        ("/Users/test/Dropbox/notes.txt", .dropbox),
        ("/Users/test/Dropbox/Projects/a/b/notes.txt", .dropbox),
        // Any account name works: the classifier cannot know which user the extension runs as.
        ("/Users/another.person/Library/CloudStorage/Dropbox/notes.txt", .dropbox),
        ("/Users/another.person/Library/Mobile Documents/com~apple~CloudDocs/notes.txt", .iCloudDrive),
        // The same volume through its data-volume path.
        ("/System/Volumes/Data/Users/test/Dropbox/notes.txt", .dropbox),
        ("/System/Volumes/Data/Users/test/Library/Mobile Documents/com~apple~CloudDocs/notes.txt", .iCloudDrive),
        // Lexical resolution, no file system involved.
        ("/Users/test/Documents/../Dropbox/./notes.txt", .dropbox),
        ("/Users//test///Library/CloudStorage/Box-Box/notes.txt", .box)
    ])
    func recognizesKnownSyncLocations(path: String, expected: PreviewSyncProvider) {
        #expect(provider(path) == expected)
    }

    @Test(arguments: [
        "/Users/test/Documents/notes.txt",
        "/Users/test/Desktop/notes.txt",
        "/Users/test/Library/Application Support/notes.txt",
        // Lookalike components never match: matching is by whole component.
        "/Users/test/Library/Mobile Documents Backup/notes.txt",
        "/Users/test/Library/Mobile Document/notes.txt",
        "/Users/test/Library/mobile documents/notes.txt",
        "/Users/test/Library/CloudStorages/Dropbox/notes.txt",
        "/Users/test/Library/CloudStorage-Dropbox/notes.txt",
        "/Users/test/Library/Preferences/CloudStorage/Dropbox/notes.txt",
        "/Users/test/Dropbox-Old/notes.txt",
        "/Users/test/MyDropbox/notes.txt",
        "/Users/test/Documents/Dropbox/notes.txt",
        "/Users/test/Dropbox",
        "/Users/test/Library/CloudStorage/Dropbox",
        "/Users/test/Library/CloudStorage",
        "/Users/test/Library/Mobile Documents",
        // Not under a user's home.
        "/Library/Mobile Documents/notes.txt",
        "/Library/CloudStorage/Dropbox/notes.txt",
        "/Dropbox/notes.txt",
        "/Volumes/Dropbox/notes.txt",
        "/Volumes/External/Users/test/Dropbox/notes.txt",
        "/private/var/Users/test/Dropbox/notes.txt",
        "/System/Volumes/Data/Library/Mobile Documents/notes.txt",
        "/System/Volumes/Preboot/Users/test/Dropbox/notes.txt",
        "/tmp/Users/test/Dropbox/notes.txt",
        "/"
    ])
    func rejectsNearMisses(path: String) {
        #expect(provider(path) == nil, "\(path)")
    }

    @Test func lookalikeProviderFoldersAreOtherNotTheKnownProvider() {
        for folder in ["Boxes", "BoxCryptor", "Dropboxes", "GoogleDriveFS", "OneDrivePersonal", "box-Box", "dropbox"] {
            #expect(provider("/Users/test/Library/CloudStorage/\(folder)/notes.txt") == .other, "\(folder)")
        }
    }

    @Test func nonFileAndRelativeURLsAreNeverSynced() {
        let urls: [URL?] = [
            URL(string: "https://example.com/Users/test/Dropbox/notes.txt"),
            URL(string: "http://localhost/Users/test/Dropbox/notes.txt"),
            URL(string: "ftp://example.com/Users/test/Dropbox/notes.txt"),
            URL(string: "file:Users/test/Dropbox/notes.txt"),
            URL(string: "file://remote.example.com/Users/test/Dropbox/notes.txt"),
            URL(string: "Users/test/Dropbox/notes.txt"),
            URL(string: "/Users/test/Dropbox/notes.txt")
        ]
        for url in urls.compactMap({ $0 }) {
            #expect(SyncFolderLocation.provider(for: url) == nil, "\(url)")
        }
        #expect(SyncFolderLocation.provider(for: URL(string: "file:///Users/test/Dropbox/notes.txt")!) == .dropbox)
        #expect(SyncFolderLocation.provider(for: URL(string: "file://localhost/Users/test/Dropbox/notes.txt")!) == .dropbox)
    }

    @Test func percentEncodedAndNonASCIIComponentsAreDecodedBeforeMatching() {
        let encoded = URL(string: "file:///Users/test/Library/Mobile%20Documents/com~apple~CloudDocs/caf%C3%A9.txt")!
        #expect(SyncFolderLocation.provider(for: encoded) == .iCloudDrive)
        #expect(provider("/Users/tést/Dropbox/日本語/😀.txt") == .dropbox)
        // An encoded separator stays inside one component, so it cannot split a lookalike into a synced path.
        #expect(SyncFolderLocation.provider(for: URL(string: "file:///Users/test/Library/Mobile%2FDocuments/notes.txt")!) == nil)
    }

    // MARK: Pipeline

    private static let secretText = "first\npassword: synthetic-field-value\nlast\n"
    private static let plainText = "first\nnothing to hide\nlast\n"

    private func presentation(path: String, text: String, preferences: PreviewPreferencesSnapshot = .defaults) async -> PreviewOutcome {
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                       reader: BytesReader(data: Data(text.utf8)))
        return await pipeline.preview(url: URL(fileURLWithPath: path, isDirectory: false), preferences: preferences)
    }

    @Test(arguments: [
        ("/Users/test/Dropbox/notes.txt", PreviewSyncProvider.dropbox),
        ("/Users/test/Library/Mobile Documents/com~apple~CloudDocs/notes.txt", .iCloudDrive),
        ("/Users/test/Library/CloudStorage/OneDrive-Personal/notes.txt", .oneDrive),
        ("/Users/test/Library/CloudStorage/SynologyDrive-nas/notes.txt", .other)
    ])
    func aSyncedFileThatConcealedSecretsGetsAWarningFirst(path: String, expected: PreviewSyncProvider) async {
        guard case .ready(let result) = await presentation(path: path, text: Self.secretText) else {
            Issue.record("expected a ready preview for \(path)")
            return
        }
        #expect(result.redactionCount == 1)
        #expect(result.findings.map(\.kind) == [.secretSyncedFolder, .secretSensitiveField])
        let warning = result.findings[0]
        #expect(warning.severity == .warning)
        #expect(warning.count == 1)
        #expect(warning.lines.isEmpty)
        #expect(warning.detail == .syncProvider(expected))
        #expect(result.findings[1].lines == [2])
    }

    @Test func syncedFilesWithoutSecretsAndSecretsOutsideSyncedFoldersGetNoWarning() async {
        guard case .ready(let clean) = await presentation(path: "/Users/test/Dropbox/notes.txt", text: Self.plainText),
              case .ready(let local) = await presentation(path: "/Users/test/Documents/notes.txt", text: Self.secretText) else {
            Issue.record("expected ready previews")
            return
        }
        #expect(clean.redactionCount == 0)
        #expect(clean.findings.isEmpty)
        #expect(local.redactionCount == 1)
        #expect(local.findings.map(\.kind) == [.secretSensitiveField])
    }

    @Test func theCloudStorageFolderNameNeverReachesThePresentation() async {
        let folder = "GoogleDrive-someone@example.com"
        let outcome = await presentation(path: "/Users/test/Library/CloudStorage/\(folder)/My Drive/notes.txt", text: Self.secretText)
        guard case .ready(let result) = outcome else { Issue.record("expected a ready preview"); return }
        #expect(result.findings.first?.detail == .syncProvider(.googleDrive))
        for visible in [result.text, String(describing: result.findings), String(describing: result)] {
            #expect(!visible.contains("someone"))
            #expect(!visible.contains("example.com"))
            #expect(!visible.contains(folder))
        }
        #expect(!result.text.contains("My Drive"))
    }

    @Test func structuredFilesInSyncedFoldersAlsoGetTheWarning() async {
        let source = #"{"password":"synthetic-field-value","name":"visible"}"#
        guard case .ready(let result) = await presentation(path: "/Users/test/Dropbox/config.json", text: source) else {
            Issue.record("expected a ready JSON preview")
            return
        }
        #expect(result.findings.map(\.kind) == [.secretSyncedFolder, .secretSensitiveField])
    }

    @Test func disabledTypesInSyncedFoldersStayDisabledWithoutAFinding() async {
        var disabled = PreviewPreferencesSnapshot.defaults
        disabled.setEnabled(false, for: .plainText)
        #expect(await presentation(path: "/Users/test/Dropbox/notes.txt", text: Self.secretText, preferences: disabled)
                == .disabledByUser(.plainText))
    }
}
