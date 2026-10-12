import Foundation
import Testing
import UniformTypeIdentifiers
import PreviewContracts
@testable import PreviewFormats

@Suite("Data format catalog")
struct DataCatalogTests {
    private let catalog = FormatCatalog.standard

    @Test func everyDataFormatHasOneCatalogEntryAndOneRegistration() {
        let identifiers = FormatID.dataSummaryFormats
        #expect(identifiers.count == 9)
        for identifier in identifiers {
            #expect(catalog.descriptor(for: identifier) != nil, "\(identifier.rawValue)")
            #expect(DataFormatAdapters.registrations.filter { $0.formatID == identifier }.count == 1, "\(identifier.rawValue)")
            #expect(StandardFormatAdapters.registrations.contains { $0.formatID == identifier })
        }
        #expect(Set(DataFormatAdapters.registrations.map(\.formatID)) == identifiers)
    }

    @Test func identifiersAndSuffixesAreStable() {
        let expected: [FormatID: [String]] = [
            .parquet: ["parquet"], .avro: ["avro"], .arrow: ["arrow", "feather", "arrows"], .numpy: ["npy"],
            .numpyArchive: ["npz"], .har: ["har"], .geoJSON: ["geojson"], .gpx: ["gpx"], .kml: ["kml", "kmz"]
        ]
        #expect(Set(expected.keys.map(\.rawValue)) == ["data.parquet", "data.avro", "data.arrow", "data.numpy",
                                                      "data.numpy-archive", "data.har", "data.geojson", "data.gpx", "data.kml"])
        for (identifier, suffixes) in expected {
            #expect(catalog.descriptor(for: identifier)?.suffixAliases == suffixes, "\(identifier.rawValue)")
        }
    }

    @Test func thumbnailPoliciesFollowTheContentDecision() {
        for identifier in [FormatID.parquet, .avro, .arrow, .numpy, .numpyArchive] {
            #expect(catalog.descriptor(for: identifier)?.thumbnail == .content, "\(identifier.rawValue)")
        }
        for identifier in [FormatID.har, .geoJSON, .gpx, .kml] {
            #expect(catalog.descriptor(for: identifier)?.thumbnail == .generic, "\(identifier.rawValue)")
        }
    }

    @Test func noFormatClaimsARootTypeAndEveryFormatIsSwitchableAndGrouped() {
        let roots: Set<UTType> = [.data, .item, .content]
        for identifier in FormatID.dataSummaryFormats {
            let descriptor = catalog.descriptor(for: identifier)
            #expect(descriptor?.contentTypes.allSatisfy { !roots.contains($0) } == true, "\(identifier.rawValue)")
            #expect(descriptor?.group == .structured && descriptor?.defaultEnabled == true)
            #expect(descriptor?.presentation == .text)
            #expect(descriptor?.nameKey == "format.\(identifier.rawValue).name")
            #expect(descriptor?.descriptionKey == "format.\(identifier.rawValue).description")
        }
    }

    @Test func classificationUsesSuffixesBeforeContentTypes() {
        for (name, identifier) in [("x.parquet", FormatID.parquet), ("x.feather", .arrow), ("x.arrows", .arrow), ("x.npz", .numpyArchive),
                                   ("x.GEOJSON", .geoJSON), ("x.kml", .kml), ("x.kmz", .kml)] {
            #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/" + name)) == identifier)
        }
        // Neighbouring formats keep their own identity.
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/x.json")) == .json)
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/x.xml")) == .xml)
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/x.sqlite")) == .sqlite)
        #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/x.zip")) == .zip)
    }

    @Test func importedTypesResolveInAnUnregisteredProcess() {
        // The catalog constructs declared imports itself, so a bare test process still resolves them.
        for identifier in FormatID.dataSummaryFormats {
            #expect(!(catalog.descriptor(for: identifier)?.contentTypes.isEmpty ?? true))
        }
        #expect(catalog.descriptor(for: .parquet)?.canonicalContentType.identifier == "org.apache.parquet")
        #expect(catalog.descriptor(for: .gpx)?.canonicalContentType.identifier == "com.topografix.gpx")
        #expect(catalog.descriptor(for: .avro)?.canonicalContentType.identifier == "org.webmeister.spacepane.type.avro")
    }

    @Test func onlyTheFourReadOnlyIntrospectionPragmasAreAdmittedToTheSQLiteConnection() {
        #expect(SQLiteInspectionAdapter.introspectionPragmas == ["table_xinfo", "foreign_key_list", "index_list", "index_xinfo"])
    }
}
