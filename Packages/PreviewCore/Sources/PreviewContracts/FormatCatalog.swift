import Foundation
import UniformTypeIdentifiers

public struct FormatID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let plainText = FormatID(rawValue: "text.plain")
    public static let json = FormatID(rawValue: "data.json")
    public static let jsonLines = FormatID(rawValue: "data.json-lines")
    public static let sourceCode = FormatID(rawValue: "text.source-code")
    public static let yaml = FormatID(rawValue: "data.yaml")
    public static let toml = FormatID(rawValue: "data.toml")
    public static let environment = FormatID(rawValue: "config.environment")
    public static let packageJSON = FormatID(rawValue: "config.package-json")
    public static let markdown = FormatID(rawValue: "text.markdown")
    public static let diff = FormatID(rawValue: "text.diff")
    public static let xml = FormatID(rawValue: "data.xml")
    public static let propertyList = FormatID(rawValue: "data.property-list")
    public static let strings = FormatID(rawValue: "config.strings")
    public static let stringsDictionary = FormatID(rawValue: "config.strings-dictionary")
    public static let opml = FormatID(rawValue: "data.opml")
    public static let csv = FormatID(rawValue: "data.csv")
    public static let tsv = FormatID(rawValue: "data.tsv")
    public static let subRip = FormatID(rawValue: "text.subrip")
    public static let webVTT = FormatID(rawValue: "text.webvtt")
    public static let nfo = FormatID(rawValue: "text.nfo")
    public static let jupyterNotebook = FormatID(rawValue: "text.jupyter-notebook")
    public static let iges = FormatID(rawValue: "cad.iges")
    public static let step = FormatID(rawValue: "cad.step")
    /// Text in a file whose name has no extension; macOS types every such file as plain data.
    public static let extensionlessText = FormatID(rawValue: "text.extensionless")
}

public enum FormatGroup: String, Codable, Sendable { case text, structured, database, containers, media }
public enum PresentationCapability: String, Codable, Sendable { case text, geometry }
/// `none` leaves the system icon in place: the thumbnail extension does not register the type.
/// `generic` draws a content-free glyph. `content` may draw a bounded, concealed rendering of the
/// document (text excerpt, table, or embedded cover image) when the user allows content thumbnails;
/// it falls back to the generic glyph when disabled, failed or not allowed.
public enum ThumbnailPolicy: String, Codable, Sendable { case generic, none, content }

/// The view a format opens in when its content allows it (decision 027, Q-32; owner decision D1): the companion
/// names it beside the format, and `CatalogPrimaryViewDriftTests` keeps it equal to the mode the renderer's policy
/// chooses for the format's built-in sample, so the catalog never promises a view the preview does not open.
public enum PrimaryView: String, Codable, Sendable, CaseIterable {
    case source, outline, records, rendered, summary, table, rows, plot, files, pages, diagram, geometry
}

public struct FormatDescriptor: Sendable {
    public let id: FormatID
    public let contentTypes: [UTType]
    public var canonicalContentType: UTType { contentTypes[0] }
    public let suffixAliases: [String]
    public let filenameAliases: [String]
    public let filenamePrefixes: [String]
    public let group: FormatGroup
    public let presentation: PresentationCapability
    public let thumbnail: ThumbnailPolicy
    /// Expensive formats require an explicit opt-in independently of the global file-type default.
    public let defaultEnabled: Bool
    /// The view the format opens in when its content allows it; see `PrimaryView`.
    public let primaryView: PrimaryView
    public let nameKey: String
    public let descriptionKey: String

    public init(id: FormatID, contentTypes: [UTType], suffixAliases: [String], group: FormatGroup,
                presentation: PresentationCapability = .text, thumbnail: ThumbnailPolicy = .generic,
                nameKey: String, descriptionKey: String,
                filenameAliases: [String] = [], filenamePrefixes: [String] = [], defaultEnabled: Bool = true,
                primaryView: PrimaryView = .source) {
        precondition(!contentTypes.isEmpty)
        self.id = id
        self.contentTypes = contentTypes
        self.suffixAliases = suffixAliases
        self.filenameAliases = filenameAliases
        self.filenamePrefixes = filenamePrefixes
        self.group = group
        self.presentation = presentation
        self.thumbnail = thumbnail
        self.defaultEnabled = defaultEnabled
        self.primaryView = primaryView
        self.nameKey = nameKey
        self.descriptionKey = descriptionKey
    }
}

/// A catalog content-type identifier that this host could not resolve to a declared type. The catalog keeps
/// the format (with a dynamic stand-in type, so suffix classification and settings still work) and records
/// the identifier here, so a test or the companion's diagnostics can name it instead of the process dying.
public struct UnresolvedContentType: Equatable, Sendable {
    public let format: FormatID
    public let identifier: String
    public init(format: FormatID, identifier: String) {
        self.format = format
        self.identifier = identifier
    }
}

public struct FormatCatalog: Sendable {
    public let descriptors: [FormatDescriptor]
    /// Empty on every supported host; a test asserts it. See `UnresolvedContentType`.
    public let unresolvedContentTypes: [UnresolvedContentType]

    public init(descriptors: [FormatDescriptor], unresolvedContentTypes: [UnresolvedContentType] = []) {
        precondition(Set(descriptors.map(\.id)).count == descriptors.count)
        self.descriptors = descriptors
        self.unresolvedContentTypes = unresolvedContentTypes
    }

    public func descriptor(for id: FormatID) -> FormatDescriptor? {
        descriptors.first { $0.id == id }
    }

    /// Recognized suffixes win before UTType fallback, including disabled types.
    /// Classification is metadata-only: this never reads document content.
    public func classify(url: URL, contentType: UTType? = nil) -> FormatID? {
        let name = url.lastPathComponent.lowercased()
        if let specific = descriptors.first(where: {
            $0.filenameAliases.contains(name) || $0.filenamePrefixes.contains(where: name.hasPrefix)
        }) { return specific.id }
        let suffix = url.pathExtension.lowercased()
        if let descriptor = descriptors.first(where: { $0.suffixAliases.contains(suffix) }) {
            return descriptor.id
        }
        guard let contentType else { return nil }
        // A root type says only that the name carried no known tag. It identifies a file
        // without an extension and nothing else, and it is never a conformance ancestor:
        // otherwise every image, document or unknown suffix would count as that format.
        if Self.rootContentTypes.contains(contentType) {
            guard suffix.isEmpty else { return nil }
            return descriptors.first(where: { $0.contentTypes.contains(contentType) })?.id
        }
        // Exact declared types precede conformance so a JSON choice stays independent of text.
        if let exact = descriptors.first(where: { $0.contentTypes.contains(contentType) }) { return exact.id }
        // Prefer a more specific declared ancestor over a generic text descriptor.
        // Otherwise an imported format's subtype could bypass that format's policy.
        var best: (id: FormatID, type: UTType)?
        for descriptor in descriptors {
            for type in descriptor.contentTypes where !Self.rootContentTypes.contains(type) && contentType.conforms(to: type) {
                guard let previous = best else { best = (descriptor.id, type); continue }
                if type.conforms(to: previous.type), !previous.type.conforms(to: type) {
                    best = (descriptor.id, type)
                }
            }
        }
        return best?.id
    }

    private static let rootContentTypes: Set<UTType> = [.data, .item, .content]

    public static let standard: FormatCatalog = {
        struct Resource: Decodable { let formats: [CatalogEntry] }
        guard let url = ContractResources.bundle.url(forResource: "FormatCatalog", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let resource = try? JSONDecoder().decode(Resource.self, from: bytes) else {
            preconditionFailure("Invalid bundled format catalog")
        }
        return Self.catalog(from: resource.formats)
    }()

    /// This catalog plus the entries of `data`: a JSON array of descriptor objects in the shape of the bundled
    /// catalog's `formats`. Version 1.0 keeps the two CAD descriptors outside the product catalog
    /// (`Configuration/CADFormatCatalogEntries.json`); the CAD tests and checks add them back with this.
    public func appending(entriesJSON data: Data) throws -> FormatCatalog {
        let extra = Self.catalog(from: try JSONDecoder().decode([CatalogEntry].self, from: data))
        return FormatCatalog(descriptors: descriptors + extra.descriptors,
                             unresolvedContentTypes: unresolvedContentTypes + extra.unresolvedContentTypes)
    }

    private struct CatalogEntry: Decodable {
        let id: String
        let contentTypes: [String]
        let extensions: [String]
        let group: FormatGroup
        let presentation: PresentationCapability
        let primaryView: PrimaryView
        let thumbnail: ThumbnailPolicy
        let nameKey: String
        let descriptionKey: String
        let importedContentTypes: [ImportedContentType]?
        let optionalContentTypes: [String]?
        let filenameAliases: [String]?
        let filenamePrefixes: [String]?
        let defaultEnabled: Bool?
    }

    /// `conformsTo` is one identifier or a list of parents, as UTTypeConformsTo is in the manifests.
    private struct ImportedContentType: Decodable {
        let identifier: String
        let conformsTo: [String]

        private enum CodingKeys: String, CodingKey { case identifier, conformsTo }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            identifier = try container.decode(String.self, forKey: .identifier)
            if let single = try? container.decode(String.self, forKey: .conformsTo) {
                conformsTo = [single]
            } else {
                conformsTo = try container.decode([String].self, forKey: .conformsTo)
            }
        }
    }

    private static func catalog(from entries: [CatalogEntry]) -> FormatCatalog {
        var unresolved: [UnresolvedContentType] = []
        let descriptors = entries.map { entry -> FormatDescriptor in
            let formatID = FormatID(rawValue: entry.id)
            let types = entry.contentTypes.compactMap { identifier -> UTType? in
                if let type = UTType(identifier) { return type }
                // A CLT process may run before the host's imported declarations are registered.
                // Only catalog-declared imported types receive this narrow construction path.
                if let imported = entry.importedContentTypes?.first(where: { $0.identifier == identifier }),
                   let parent = imported.conformsTo.lazy.compactMap({ UTType($0) }).first {
                    return UTType(importedAs: identifier, conformingTo: parent)
                }
                // Additional system types can be unavailable on an older supported OS.
                if entry.optionalContentTypes?.contains(identifier) == true { return nil }
                // A system identifier this host does not declare: never a fatal error in a preview process.
                // The format keeps a dynamic stand-in so suffix classification and settings still work, and
                // the identifier is recorded for the catalog test and the provider diagnostics.
                unresolved.append(UnresolvedContentType(format: formatID, identifier: identifier))
                return UTType(importedAs: identifier, conformingTo: .data)
            }
            return FormatDescriptor(id: formatID, contentTypes: types,
                suffixAliases: entry.extensions, group: entry.group, presentation: entry.presentation,
                thumbnail: entry.thumbnail, nameKey: entry.nameKey, descriptionKey: entry.descriptionKey,
                filenameAliases: entry.filenameAliases ?? [], filenamePrefixes: entry.filenamePrefixes ?? [],
                defaultEnabled: entry.defaultEnabled ?? true, primaryView: entry.primaryView)
        }
        return FormatCatalog(descriptors: descriptors, unresolvedContentTypes: unresolved)
    }
}
