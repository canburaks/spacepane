import Foundation

public enum PreferencesLocation {
    public static let snapshotFilename = "preferences.json"

    public static func appGroupSnapshotURL(identifier: String?) -> URL? {
        guard let identifier, !identifier.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { return nil }
        return container.appendingPathComponent(snapshotFilename, isDirectory: false)
    }

    public static func companionSnapshotURL() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: false)
        return support.appendingPathComponent("PreviewPreferences", isDirectory: true)
            .appendingPathComponent(snapshotFilename, isDirectory: false)
    }
}
