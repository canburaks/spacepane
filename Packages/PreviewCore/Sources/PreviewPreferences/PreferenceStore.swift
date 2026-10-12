import Foundation
import PreviewContracts

public enum PreferencesLoadState: Sendable, Equatable {
    case defaults, loaded, migrated, corrupt, unreadable, unsupportedVersion
}
public struct PreferencesLoadResult: Sendable, Equatable {
    public let snapshot: PreviewPreferencesSnapshot
    public let state: PreferencesLoadState
    public init(snapshot: PreviewPreferencesSnapshot, state: PreferencesLoadState) {
        self.snapshot = snapshot
        self.state = state
    }
}
public enum PreferencesStoreError: Error, Sendable, Equatable { case invalidSnapshot, cannotWrite }

/// The companion is the sole persistent writer. Extensions only call load().
/// An actor serializes in-process operations; atomic replacement publishes complete snapshots
/// to readers in independent app/extension processes without a long-lived shared defaults cache.
public actor PreferenceStore {
    public let url: URL
    public static let schemaVersion = 6
    private static let maxDocumentBytes = 65_536
    public init(url: URL) { self.url = url }

    public func load() -> PreferencesLoadResult {
        do {
            let data = try BoundedPreferencesData.read(at: url, maximumBytes: Self.maxDocumentBytes)
            let header = try JSONDecoder().decode(Header.self, from: data)
            let snapshot: PreviewPreferencesSnapshot
            // Every migration decodes each previously persisted field strictly and defaults only the
            // fields its schema did not have; the snapshot initializer supplies those defaults.
            switch header.schemaVersion {
            case 1, 2:
                let document = try JSONDecoder().decode(LegacyDocument.self, from: data)
                if header.schemaVersion == 2 && document.typography == nil { return fallback(.corrupt) }
                snapshot = PreviewPreferencesSnapshot(defaultEnabled: document.defaultEnabled,
                    formatOverrides: overrides(document.formatOverrides),
                    typography: document.typography?.migrated ?? PreviewTypography())
            case 3:
                let document = try JSONDecoder().decode(SchemaThreeDocument.self, from: data)
                snapshot = PreviewPreferencesSnapshot(defaultEnabled: document.defaultEnabled,
                    formatOverrides: overrides(document.formatOverrides), typography: document.typography.migrated,
                    theme: document.theme)
            case 4:
                let document = try JSONDecoder().decode(SchemaFourDocument.self, from: data)
                snapshot = PreviewPreferencesSnapshot(defaultEnabled: document.defaultEnabled,
                    formatOverrides: overrides(document.formatOverrides), typography: document.typography,
                    theme: document.theme)
            case 5:
                let document = try JSONDecoder().decode(SchemaFiveDocument.self, from: data)
                snapshot = PreviewPreferencesSnapshot(defaultEnabled: document.defaultEnabled,
                    formatOverrides: overrides(document.formatOverrides), typography: document.typography,
                    theme: document.theme, syntaxStyle: document.syntaxStyle.migrated,
                    appearanceProfiles: document.appearanceProfiles.map(\.migrated))
            case Self.schemaVersion:
                let document = try JSONDecoder().decode(Document.self, from: data)
                snapshot = PreviewPreferencesSnapshot(defaultEnabled: document.defaultEnabled,
                    formatOverrides: overrides(document.formatOverrides), typography: document.typography,
                    theme: document.theme, syntaxStyle: document.syntaxStyle,
                    appearanceProfiles: document.appearanceProfiles,
                    reloadsOnFileChange: document.reloadsOnFileChange,
                    showsContentThumbnails: document.showsContentThumbnails,
                    folderDepth: document.folderDepth, showsHiddenFolderItems: document.showsHiddenFolderItems)
            default: return fallback(.unsupportedVersion)
            }
            guard isValid(snapshot) else { return fallback(.corrupt) }
            return PreferencesLoadResult(snapshot: snapshot,
                state: header.schemaVersion == Self.schemaVersion ? .loaded : .migrated)
        } catch PreferencesReadFailure.missing {
            return PreferencesLoadResult(snapshot: .defaults, state: .defaults)
        } catch PreferencesReadFailure.oversized { return fallback(.corrupt) }
        catch is DecodingError { return fallback(.corrupt) }
        catch { return fallback(.unreadable) }
    }

    public func save(_ snapshot: PreviewPreferencesSnapshot) throws {
        guard isValid(snapshot) else { throw PreferencesStoreError.invalidSnapshot }
        let document = Document(schemaVersion: Self.schemaVersion, defaultEnabled: snapshot.defaultEnabled,
            formatOverrides: Dictionary(uniqueKeysWithValues: snapshot.formatOverrides.map { ($0.key.rawValue, $0.value) }),
            typography: snapshot.typography, theme: snapshot.theme, syntaxStyle: snapshot.syntaxStyle,
            appearanceProfiles: snapshot.appearanceProfiles,
            reloadsOnFileChange: snapshot.reloadsOnFileChange, showsContentThumbnails: snapshot.showsContentThumbnails,
            folderDepth: snapshot.folderDepth, showsHiddenFolderItems: snapshot.showsHiddenFolderItems)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(document)
            guard data.count <= Self.maxDocumentBytes else { throw PreferencesStoreError.invalidSnapshot }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch is PreferencesStoreError { throw PreferencesStoreError.invalidSnapshot }
        catch { throw PreferencesStoreError.cannotWrite }
    }

    private func fallback(_ state: PreferencesLoadState) -> PreferencesLoadResult {
        PreferencesLoadResult(snapshot: .disabledContentFallback, state: state)
    }
    private func overrides(_ stored: [String: Bool]) -> [FormatID: Bool] {
        Dictionary(uniqueKeysWithValues: stored.map { (FormatID(rawValue: $0.key), $0.value) })
    }
    private func isValid(_ snapshot: PreviewPreferencesSnapshot) -> Bool {
        snapshot.hasValidChoices && snapshot.formatOverrides.count <= 1_024
        && snapshot.formatOverrides.keys.allSatisfy { id in
            !id.rawValue.isEmpty && id.rawValue.utf8.count <= 128
            && id.rawValue.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 46 || $0 == 45 || $0 == 95 }
        }
    }
    private struct Header: Decodable { let schemaVersion: Int }
    /// Every field is required: a current-schema document that lacks one is corrupt, not defaulted.
    private struct Document: Codable {
        let schemaVersion: Int
        let defaultEnabled: Bool
        let formatOverrides: [String: Bool]
        let typography: PreviewTypography
        let theme: PreviewTheme
        let syntaxStyle: PreviewSyntaxStyle
        let appearanceProfiles: [PreviewAppearanceProfile]
        let reloadsOnFileChange: Bool
        let showsContentThumbnails: Bool
        let folderDepth: Int
        let showsHiddenFolderItems: Bool
    }
    /// Schema 5 had no color schemes or behavior fields; its syntax style and profiles use the
    /// three-field syntax style and migrate to the Standard schemes.
    private struct SchemaFiveDocument: Decodable {
        let schemaVersion: Int
        let defaultEnabled: Bool
        let formatOverrides: [String: Bool]
        let typography: PreviewTypography
        let theme: PreviewTheme
        let syntaxStyle: SchemaFiveSyntaxStyle
        let appearanceProfiles: [SchemaFiveProfile]
    }
    private struct SchemaFiveSyntaxStyle: Decodable {
        let usesColor: Bool
        let boldRoles: Set<PreviewSyntaxRole>
        let italicRoles: Set<PreviewSyntaxRole>
        var migrated: PreviewSyntaxStyle {
            PreviewSyntaxStyle(usesColor: usesColor, boldRoles: boldRoles, italicRoles: italicRoles)
        }
    }
    private struct SchemaFiveProfile: Decodable {
        struct Appearance: Decodable {
            let typography: PreviewTypography
            let theme: PreviewTheme
            let syntaxStyle: SchemaFiveSyntaxStyle
        }
        let id: UUID
        let name: String
        let appearance: Appearance
        var migrated: PreviewAppearanceProfile {
            PreviewAppearanceProfile(id: id, name: name, appearance: PreviewAppearance(
                typography: appearance.typography, theme: appearance.theme, syntaxStyle: appearance.syntaxStyle.migrated))
        }
    }
    private struct SchemaFourDocument: Decodable {
        let schemaVersion: Int
        let defaultEnabled: Bool
        let formatOverrides: [String: Bool]
        let typography: PreviewTypography
        let theme: PreviewTheme
    }
    private struct SchemaThreeDocument: Decodable {
        let schemaVersion: Int
        let defaultEnabled: Bool
        let formatOverrides: [String: Bool]
        let typography: SchemaThreeTypography
        let theme: PreviewTheme
    }
    /// Strictly decode every previous appearance field; only the newly introduced flag defaults.
    private struct SchemaThreeTypography: Decodable {
        let fontSize: Double
        let wrapsLines: Bool
        let fontFamily: String?
        let weight: PreviewFontWeight
        let italic: Bool
        let lineSpacing: Double
        let characterSpacing: Double
        let ligatures: Bool
        let tabWidth: Int

        private enum CodingKeys: String, CodingKey {
            case fontSize, wrapsLines, fontFamily, weight, italic, lineSpacing, characterSpacing, ligatures, tabWidth
        }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            fontSize = try values.decode(Double.self, forKey: .fontSize)
            wrapsLines = try values.decode(Bool.self, forKey: .wrapsLines)
            fontFamily = try values.decode(String?.self, forKey: .fontFamily)
            weight = try values.decode(PreviewFontWeight.self, forKey: .weight)
            italic = try values.decode(Bool.self, forKey: .italic)
            lineSpacing = try values.decode(Double.self, forKey: .lineSpacing)
            characterSpacing = try values.decode(Double.self, forKey: .characterSpacing)
            ligatures = try values.decode(Bool.self, forKey: .ligatures)
            tabWidth = try values.decode(Int.self, forKey: .tabWidth)
        }
        var migrated: PreviewTypography {
            PreviewTypography(fontSize: fontSize, wrapsLines: wrapsLines, fontFamily: fontFamily,
                weight: weight, italic: italic, lineSpacing: lineSpacing, characterSpacing: characterSpacing,
                ligatures: ligatures, tabWidth: tabWidth)
        }
    }
    /// Previous schemas only stored size/wrapping; migrations do not decode them as current typography.
    private struct LegacyDocument: Decodable {
        let schemaVersion: Int
        let defaultEnabled: Bool
        let formatOverrides: [String: Bool]
        let typography: LegacyTypography?
    }
    private struct LegacyTypography: Decodable {
        let fontSize: Double
        let wrapsLines: Bool
        var migrated: PreviewTypography { PreviewTypography(fontSize: fontSize, wrapsLines: wrapsLines) }
    }
}
