import Foundation
import PreviewContracts

public enum AppearanceThemeError: Error, Equatable, Sendable {
    case tooLarge, invalidDocument, unsupportedVersion, cannotRead
}

/// JSON appearance exchange has no URLs, fonts to install, parser settings, scripts, file policy or file contents.
///
/// Version 2 adds the light and dark color-scheme choices, which are identifiers of built-in palettes and
/// never color values. Version 1 files, which predate schemes, still import and use the Standard schemes.
public enum AppearanceThemeCodec {
    public static let schemaVersion = 2
    /// Versions an import accepts; export always writes `schemaVersion`.
    public static let supportedImportVersions: ClosedRange<Int> = 1...2
    public static let maximumDocumentBytes = 16_384

    private static let typographyKeys: Set<String> = ["fontSize", "wrapsLines", "fontFamily", "weight", "italic",
        "lineSpacing", "characterSpacing", "ligatures", "tabWidth", "showsLineNumbers"]
    private static let versionOneSyntaxKeys: Set<String> = ["usesColor", "boldRoles", "italicRoles"]
    private static let versionTwoSyntaxKeys: Set<String> = versionOneSyntaxKeys.union(["lightScheme", "darkScheme"])

    public static func encode(_ appearance: PreviewAppearance) throws -> Data {
        guard appearance.isValid else { throw AppearanceThemeError.invalidDocument }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(Document(schemaVersion: schemaVersion, appearance: appearance))
        guard data.count <= maximumDocumentBytes else { throw AppearanceThemeError.tooLarge }
        return data
    }

    public static func decode(_ data: Data) throws -> PreviewAppearance {
        guard data.count <= maximumDocumentBytes else { throw AppearanceThemeError.tooLarge }
        do {
            let decoder = JSONDecoder()
            let header = try decoder.decode(Header.self, from: data)
            guard supportedImportVersions.contains(header.schemaVersion) else { throw AppearanceThemeError.unsupportedVersion }
            // Reject unknown fields as well as incomplete payloads; imports are an explicit inert schema.
            let root = try JSONSerialization.jsonObject(with: data)
            guard let root = root as? [String: Any], Set(root.keys) == ["schemaVersion", "appearance"],
                  let appearance = root["appearance"] as? [String: Any],
                  Set(appearance.keys) == ["typography", "theme", "syntaxStyle"],
                  let typography = appearance["typography"] as? [String: Any],
                  Set(typography.keys) == typographyKeys,
                  let syntax = appearance["syntaxStyle"] as? [String: Any] else {
                throw AppearanceThemeError.invalidDocument
            }
            let imported: PreviewAppearance
            if header.schemaVersion == schemaVersion {
                guard Set(syntax.keys) == versionTwoSyntaxKeys else { throw AppearanceThemeError.invalidDocument }
                imported = try decoder.decode(Document.self, from: data).appearance
            } else {
                guard Set(syntax.keys) == versionOneSyntaxKeys else { throw AppearanceThemeError.invalidDocument }
                imported = try decoder.decode(VersionOneDocument.self, from: data).appearance.migrated
            }
            guard imported.isValid else { throw AppearanceThemeError.invalidDocument }
            return imported
        } catch let error as AppearanceThemeError { throw error }
        catch { throw AppearanceThemeError.invalidDocument }
    }

    private struct Header: Decodable { let schemaVersion: Int }
    private struct Document: Codable {
        let schemaVersion: Int
        let appearance: PreviewAppearance
    }

    /// Version 1 stored three syntax-style fields; its files import as the Standard schemes.
    private struct VersionOneDocument: Decodable {
        struct Appearance: Decodable {
            struct Syntax: Decodable {
                let usesColor: Bool
                let boldRoles: Set<PreviewSyntaxRole>
                let italicRoles: Set<PreviewSyntaxRole>
            }
            let typography: PreviewTypography
            let theme: PreviewTheme
            let syntaxStyle: Syntax
            var migrated: PreviewAppearance {
                PreviewAppearance(typography: typography, theme: theme,
                    syntaxStyle: PreviewSyntaxStyle(usesColor: syntaxStyle.usesColor,
                        boldRoles: syntaxStyle.boldRoles, italicRoles: syntaxStyle.italicRoles))
            }
        }
        let schemaVersion: Int
        let appearance: Appearance
    }
}

/// Blocking file reads are confined to this actor, separate from the companion's main-actor UI.
public actor AppearanceThemeReader {
    public init() {}

    public func read(at url: URL) throws -> PreviewAppearance {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try BoundedPreferencesData.read(at: url, maximumBytes: AppearanceThemeCodec.maximumDocumentBytes)
            return try AppearanceThemeCodec.decode(data)
        } catch PreferencesReadFailure.oversized { throw AppearanceThemeError.tooLarge }
        catch let error as AppearanceThemeError { throw error }
        catch { throw AppearanceThemeError.cannotRead }
    }
}
