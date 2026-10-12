import Foundation
import Testing
import PreviewContracts
import PreviewFormats

@Suite("3MF adapter")
struct ThreeMFAdapterTests {
    private let cube = MeshFixtures.cube(size: 10)
    private let production = "xmlns:p=\"\(MeshFixtures.productionNamespace)\""

    private func parse(_ data: Data, budget: PreviewBudget = MeshLimits.requestBudget) throws -> PreviewMesh {
        try ThreeMFAdapter().parse(FileBytes(data: data), context: RequestContext(budget: budget))
    }

    private func package(unit: String? = "millimeter", resources: String, build: String, namespaces: String = "",
                         extraParts: [(name: String, data: Data)] = []) -> Data {
        MeshFixtures.threeMF(model: MeshFixtures.modelXML(unit: unit, resources: resources, build: build, extraNamespaces: namespaces),
                             extraParts: extraParts)
    }

    private var cubeObject: String { MeshFixtures.meshObject(id: 1, vertices: cube.vertices, triangles: cube.triangles) }

    // MARK: Meshes, units and transforms

    @Test func readsMeshesFromDeflatedAndStoredPackages() throws {
        for deflate in [true, false] {
            let data = MeshFixtures.threeMF(model: MeshFixtures.modelXML(resources: cubeObject, build: "<item objectid=\"1\"/>"), deflate: deflate)
            let mesh = try parse(data)
            MeshFixtures.expectWellFormed(mesh)
            #expect(MeshFixtures.triangleCount(mesh) == 12)
            #expect(mesh.faceCount == 12)
            #expect(MeshFixtures.extent(mesh) == SIMD3<Double>(10, 10, 10))
        }
    }

    @Test(arguments: [("micron", 0.001), ("millimeter", 1.0), ("centimeter", 10.0), ("inch", 25.4), ("foot", 304.8), ("meter", 1000.0)])
    func unitIsConvertedToMillimetres(unit: String, factor: Double) throws {
        let mesh = try parse(package(unit: unit, resources: cubeObject, build: "<item objectid=\"1\"/>"))
        for axis in 0..<3 { #expect(abs(MeshFixtures.extent(mesh)[axis] - 10 * factor) < 1e-9 * factor) }
    }

    @Test func missingUnitDefaultsToMillimetresAndUnknownUnitsAreRejected() throws {
        let mesh = try parse(package(unit: nil, resources: cubeObject, build: "<item objectid=\"1\"/>"))
        #expect(MeshFixtures.extent(mesh) == SIMD3<Double>(10, 10, 10))
        #expect(throws: PreviewFailure.malformedDocument) {
            try parse(package(unit: "furlong", resources: cubeObject, build: "<item objectid=\"1\"/>"))
        }
    }

    @Test func buildItemTransformUsesTheSpecificationsRowVectorConvention() throws {
        let box = MeshFixtures.cube(size: 2)
        let stretched = box.vertices.map { SIMD3<Double>($0.x * 2, $0.y, $0.z) }   // 4 x 2 x 2
        let object = MeshFixtures.meshObject(id: 1, vertices: stretched, triangles: box.triangles)
        // Quarter turn about z then a translation: x' = -y, y' = x.
        let mesh = try parse(package(resources: object, build: "<item objectid=\"1\" transform=\"0 1 0 -1 0 0 0 0 1 100 0 0\"/>"))
        #expect(MeshFixtures.extent(mesh) == SIMD3<Double>(2, 4, 2))
        #expect(mesh.bounds.minimum == SIMD3<Double>(99, -2, -1))
    }

    @Test func componentsComposeTheirTransformWithTheItemInTheRightOrder() throws {
        let components = "<object id=\"2\"><components><component objectid=\"1\"/>"
            + "<component objectid=\"1\" transform=\"1 0 0 0 1 0 0 0 1 30 0 0\"/></components></object>"
        // The item turns the whole object a quarter about z: the second instance moves from +x to +y.
        let mesh = try parse(package(resources: cubeObject + components,
                                     build: "<item objectid=\"2\" transform=\"0 1 0 -1 0 0 0 0 1 0 0 5\"/>"))
        #expect(MeshFixtures.triangleCount(mesh) == 24)
        #expect(mesh.bounds.minimum == SIMD3<Double>(-5, -5, 0))
        #expect(mesh.bounds.maximum == SIMD3<Double>(5, 35, 10))
    }

    @Test func nestedComponentsAndRepeatedItemsInstantiateEveryCopy() throws {
        let nested = "<object id=\"2\"><components><component objectid=\"1\" transform=\"1 0 0 0 1 0 0 0 1 20 0 0\"/></components></object>"
            + "<object id=\"3\"><components><component objectid=\"2\" transform=\"1 0 0 0 1 0 0 0 1 0 20 0\"/></components></object>"
        let mesh = try parse(package(resources: cubeObject + nested,
                                     build: "<item objectid=\"3\"/><item objectid=\"1\"/><item objectid=\"3\" transform=\"1 0 0 0 1 0 0 0 1 0 0 40\"/>"))
        #expect(MeshFixtures.triangleCount(mesh) == 36)
        #expect(mesh.bounds.maximum == SIMD3<Double>(25, 25, 45))
    }

    @Test func emptyBuildDrawsObjectsNoComponentUses() throws {
        let used = "<object id=\"2\"><components><component objectid=\"1\" transform=\"1 0 0 0 1 0 0 0 1 20 0 0\"/></components></object>"
        let mesh = try parse(package(resources: cubeObject + used, build: ""))
        #expect(MeshFixtures.triangleCount(mesh) == 12)
        #expect(mesh.bounds.maximum.x == 25)
    }

    @Test func supportObjectsAreNotDrawn() throws {
        let support = MeshFixtures.meshObject(id: 2, vertices: cube.vertices.map { $0 + SIMD3(100, 0, 0) }, triangles: cube.triangles, type: "support")
        let mesh = try parse(package(resources: cubeObject + support, build: "<item objectid=\"1\"/><item objectid=\"2\"/>"))
        #expect(MeshFixtures.triangleCount(mesh) == 12)
        #expect(mesh.bounds.maximum.x == 5)
        #expect(throws: PreviewFailure.malformedDocument) { try parse(package(resources: support, build: "<item objectid=\"2\"/>")) }
    }

    @Test func extensionElementsAndMetadataAreIgnored() throws {
        let colors = "<m:colorgroup xmlns:m=\"http://schemas.microsoft.com/3dmanufacturing/material/2015/02\" id=\"9\">"
            + "<m:color color=\"#FF0000\"/><m:triangle v1=\"0\" v2=\"1\" v3=\"2\"/></m:colorgroup>"
        let data = package(resources: colors + cubeObject, build: "<item objectid=\"1\"/>",
                           extraParts: [("Metadata/thumbnail.png", Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])),
                                        ("Metadata/note.txt", Data("password=synthetic-3mf-secret".utf8))])
        let mesh = try parse(data)
        #expect(MeshFixtures.triangleCount(mesh) == 12)
        #expect(mesh.positions.count == 24)
    }

    // MARK: Component graphs

    @Test func componentCyclesAreRejected() throws {
        let direct = "<object id=\"1\"><components><component objectid=\"1\"/></components></object>"
        #expect(throws: PreviewFailure.malformedDocument) { try parse(package(resources: direct, build: "<item objectid=\"1\"/>")) }
        let loop = "<object id=\"1\"><components><component objectid=\"2\"/></components></object>"
            + "<object id=\"2\"><components><component objectid=\"3\"/></components></object>"
            + "<object id=\"3\"><components><component objectid=\"1\"/></components></object>"
        #expect(throws: PreviewFailure.malformedDocument) { try parse(package(resources: loop, build: "<item objectid=\"2\"/>")) }
        // A cycle that also holds geometry is no more acceptable.
        let withMesh = MeshFixtures.meshObject(id: 4, vertices: cube.vertices, triangles: cube.triangles)
            .replacingOccurrences(of: "</object>", with: "<components><component objectid=\"4\"/></components></object>")
        #expect(throws: PreviewFailure.malformedDocument) { try parse(package(resources: withMesh, build: "<item objectid=\"4\"/>")) }
    }

    @Test func sharingAnObjectTwiceIsNotACycle() throws {
        let diamond = "<object id=\"2\"><components><component objectid=\"1\"/></components></object>"
            + "<object id=\"3\"><components><component objectid=\"1\" transform=\"1 0 0 0 1 0 0 0 1 20 0 0\"/></components></object>"
            + "<object id=\"4\"><components><component objectid=\"2\"/><component objectid=\"3\"/></components></object>"
        let mesh = try parse(package(resources: cubeObject + diamond, build: "<item objectid=\"4\"/>"))
        #expect(MeshFixtures.triangleCount(mesh) == 24)
    }

    @Test func excessiveDepthAndInstancingAreBounded() throws {
        var chain = cubeObject
        for id in 2...40 { chain += "<object id=\"\(id)\"><components><component objectid=\"\(id - 1)\"/></components></object>" }
        #expect(throws: PreviewFailure.structureTooDeep) { try parse(package(resources: chain, build: "<item objectid=\"40\"/>")) }
        // Doubling at each level: a few dozen elements describe millions of instances. With no geometry
        // to count, the instance ceiling stops it; with geometry, the triangle ceiling does first.
        func doubling(leaf: String) -> String {
            var resources = leaf
            for id in 2...25 { resources += "<object id=\"\(id)\"><components><component objectid=\"\(id - 1)\"/><component objectid=\"\(id - 1)\"/></components></object>" }
            return resources
        }
        #expect(throws: PreviewFailure.tooManyNodes) { try parse(package(resources: doubling(leaf: "<object id=\"1\"/>"), build: "<item objectid=\"25\"/>")) }
        #expect(throws: PreviewFailure.geometryTooComplex) { try parse(package(resources: doubling(leaf: cubeObject), build: "<item objectid=\"25\"/>")) }
    }

    // MARK: Production extension and package layout

    @Test func followsComponentsIntoOtherModelPartsOfTheSameArchive() throws {
        let partModel = MeshFixtures.modelXML(unit: "millimeter", resources: cubeObject, build: "")
        let root = "<object id=\"7\"><components><component p:path=\"/3D/Objects/part.model\" objectid=\"1\" transform=\"1 0 0 0 1 0 0 0 1 50 0 0\"/></components></object>"
        let data = package(resources: root, build: "<item objectid=\"7\"/>", namespaces: " \(production)",
                           extraParts: [("3D/Objects/part.model", Data(partModel.utf8))])
        let mesh = try parse(data)
        #expect(MeshFixtures.triangleCount(mesh) == 12)
        #expect(mesh.bounds.minimum.x == 45)
        // A path outside the archive is an error, never a lookup elsewhere.
        let missing = package(resources: root.replacingOccurrences(of: "/3D/Objects/part.model", with: "/3D/Objects/absent.model"),
                              build: "<item objectid=\"7\"/>", namespaces: " \(production)")
        #expect(throws: PreviewFailure.malformedDocument) { try parse(missing) }
        let traversal = package(resources: root.replacingOccurrences(of: "/3D/Objects/part.model", with: "../../etc/hosts"),
                                build: "<item objectid=\"7\"/>", namespaces: " \(production)")
        #expect(throws: PreviewFailure.malformedDocument) { try parse(traversal) }
    }

    @Test func modelPartComesFromTheRelationshipsOrTheDefaultPath() throws {
        let model = MeshFixtures.modelXML(resources: cubeObject, build: "<item objectid=\"1\"/>")
        let relocated = MeshFixtures.relationships.replacingOccurrences(of: "/3D/3dmodel.model", with: "/Models/main.model")
        let data = MeshFixtures.zip([("_rels/.rels", Data(relocated.utf8)), ("Models/main.model", Data(model.utf8))])
        #expect(MeshFixtures.triangleCount(try parse(data)) == 12)
        // No relationships part at all: the conventional location is used.
        #expect(MeshFixtures.triangleCount(try parse(MeshFixtures.threeMF(model: model, relationships: nil))) == 12)
        // Part names are case-insensitive.
        let lowercase = MeshFixtures.zip([("_rels/.rels", Data(MeshFixtures.relationships.utf8)), ("3d/3DMODEL.model", Data(model.utf8))])
        #expect(MeshFixtures.triangleCount(try parse(lowercase)) == 12)
        // A relationship naming an absent part, or no model at all, is not a 3MF.
        let absent = MeshFixtures.zip([("_rels/.rels", Data(relocated.utf8)), ("3D/3dmodel.model", Data(model.utf8))])
        #expect(throws: PreviewFailure.malformedDocument) { try parse(absent) }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(MeshFixtures.zip([("readme.txt", Data("hello".utf8))])) }
    }

    // MARK: Malformed content

    @Test func rejectsStructuralAndNumericErrors() throws {
        let build = "<item objectid=\"1\"/>"
        func resources(vertex: String = "<vertex x=\"0\" y=\"0\" z=\"0\"/><vertex x=\"1\" y=\"0\" z=\"0\"/><vertex x=\"0\" y=\"1\" z=\"0\"/>",
                       triangle: String = "<triangle v1=\"0\" v2=\"1\" v3=\"2\"/>") -> String {
            "<object id=\"1\"><mesh><vertices>\(vertex)</vertices><triangles>\(triangle)</triangles></mesh></object>"
        }
        #expect(MeshFixtures.triangleCount(try parse(package(resources: resources(), build: build))) == 1)
        let bad: [(String, String, String)] = [
            ("index past vertices", resources(triangle: "<triangle v1=\"0\" v2=\"1\" v3=\"3\"/>"), build),
            ("negative index", resources(triangle: "<triangle v1=\"0\" v2=\"1\" v3=\"-1\"/>"), build),
            ("missing index", resources(triangle: "<triangle v1=\"0\" v2=\"1\"/>"), build),
            ("fractional index", resources(triangle: "<triangle v1=\"0\" v2=\"1\" v3=\"1.5\"/>"), build),
            ("nan coordinate", resources(vertex: "<vertex x=\"nan\" y=\"0\" z=\"0\"/><vertex x=\"1\" y=\"0\" z=\"0\"/><vertex x=\"0\" y=\"1\" z=\"0\"/>"), build),
            ("infinite coordinate", resources(vertex: "<vertex x=\"1e999\" y=\"0\" z=\"0\"/><vertex x=\"1\" y=\"0\" z=\"0\"/><vertex x=\"0\" y=\"1\" z=\"0\"/>"), build),
            ("huge coordinate", resources(vertex: "<vertex x=\"5e12\" y=\"0\" z=\"0\"/><vertex x=\"1\" y=\"0\" z=\"0\"/><vertex x=\"0\" y=\"1\" z=\"0\"/>"), build),
            ("missing coordinate", resources(vertex: "<vertex x=\"0\" y=\"0\"/><vertex x=\"1\" y=\"0\" z=\"0\"/><vertex x=\"0\" y=\"1\" z=\"0\"/>"), build),
            ("unknown build object", resources(), "<item objectid=\"9\"/>"),
            ("item without object", resources(), "<item/>"),
            ("object id zero", resources().replacingOccurrences(of: "id=\"1\"", with: "id=\"0\""), build),
            ("short transform", resources(), "<item objectid=\"1\" transform=\"1 0 0 0 1 0 0 0 1 0 0\"/>"),
            ("non-numeric transform", resources(), "<item objectid=\"1\" transform=\"1 0 0 0 1 0 0 0 1 0 0 x\"/>"),
            ("infinite transform", resources(), "<item objectid=\"1\" transform=\"1 0 0 0 1 0 0 0 1 0 0 1e999\"/>"),
            ("duplicate object", resources() + resources(), build),
        ]
        for (name, content, items) in bad {
            #expect(throws: PreviewFailure.malformedDocument, "\(name)") { try parse(package(resources: content, build: items)) }
        }
        // Only degenerate triangles remain once collinear ones are dropped.
        let sliver = resources(vertex: "<vertex x=\"0\" y=\"0\" z=\"0\"/><vertex x=\"1\" y=\"0\" z=\"0\"/><vertex x=\"2\" y=\"0\" z=\"0\"/>")
        #expect(throws: PreviewFailure.malformedDocument) { try parse(package(resources: sliver, build: build)) }
        // An object with no geometry at all.
        #expect(throws: PreviewFailure.malformedDocument) { try parse(package(resources: "<object id=\"1\"/>", build: build)) }
    }

    @Test func rejectsPackagesThatAreNotValid3MF() throws {
        #expect(throws: PreviewFailure.malformedDocument) { try parse(Data()) }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(Data("PK\u{3}\u{4}not really a zip file at all".utf8)) }
        let valid = package(resources: cubeObject, build: "<item objectid=\"1\"/>")
        #expect(throws: PreviewFailure.malformedDocument) { try parse(valid.dropLast(10)) }
        #expect(throws: PreviewFailure.malformedDocument) { try parse(valid.prefix(valid.count / 2)) }
        // A model part that is not XML, and XML that is not a model.
        let notXML = MeshFixtures.zip([("_rels/.rels", Data(MeshFixtures.relationships.utf8)), ("3D/3dmodel.model", Data("not xml <<<".utf8))])
        #expect(throws: PreviewFailure.malformedDocument) { try parse(notXML) }
        let wrongRoot = MeshFixtures.threeMF(model: "<?xml version=\"1.0\"?><something/>")
        #expect(throws: PreviewFailure.malformedDocument) { try parse(wrongRoot) }
        // A corrupted checksum in the model part.
        var corrupt = valid
        let index = corrupt.range(of: Data("PK\u{1}\u{2}".utf8), options: .backwards)!.lowerBound
        corrupt[index + 16] ^= 0xFF
        #expect(throws: PreviewFailure.malformedDocument) { try parse(corrupt) }
    }

    // MARK: XML safety

    @Test func documentTypeDeclarationsAndEntitiesAreRefused() throws {
        let build = "<item objectid=\"1\"/>"
        let external = "<!DOCTYPE model [<!ENTITY xxe SYSTEM \"file:///etc/hosts\">]>"
        let model = MeshFixtures.modelXML(resources: cubeObject, build: build, doctype: external)
            .replacingOccurrences(of: "<build>", with: "<metadata name=\"Title\">&xxe;</metadata><build>")
        #expect(throws: PreviewFailure.malformedDocument) { try parse(MeshFixtures.threeMF(model: model)) }
        let internalEntity = MeshFixtures.modelXML(resources: cubeObject, build: build, doctype: "<!DOCTYPE model [<!ENTITY a \"aaaa\">]>")
        #expect(throws: PreviewFailure.malformedDocument) { try parse(MeshFixtures.threeMF(model: internalEntity)) }
        // Expansion that doubles at every level never gets to expand.
        var laughs = "<!DOCTYPE model [<!ENTITY a0 \"lol\">"
        for level in 1...9 { laughs += "<!ENTITY a\(level) \"" + String(repeating: "&a\(level - 1);", count: 10) + "\">" }
        laughs += "]>"
        let bomb = MeshFixtures.modelXML(resources: cubeObject, build: build, doctype: laughs)
            .replacingOccurrences(of: "<build>", with: "<metadata name=\"Title\">&a9;</metadata><build>")
        let started = ContinuousClock.now
        #expect(throws: PreviewFailure.malformedDocument) { try parse(MeshFixtures.threeMF(model: bomb)) }
        #expect(ContinuousClock.now - started < .seconds(5))
        // Even a declaration-free DOCTYPE, or one naming an external subset, is refused.
        for doctype in ["<!DOCTYPE model>", "<!DOCTYPE model SYSTEM \"file:///etc/passwd\">"] {
            let plain = MeshFixtures.modelXML(resources: cubeObject, build: build, doctype: doctype)
            #expect(throws: PreviewFailure.malformedDocument, "\(doctype)") { try parse(MeshFixtures.threeMF(model: plain)) }
        }
        // The relationships part follows the same rule.
        let relationships = MeshFixtures.relationships.replacingOccurrences(of: "<Relationships", with: "<!DOCTYPE r [<!ENTITY e \"x\">]><Relationships")
        let ordinary = MeshFixtures.modelXML(resources: cubeObject, build: build)
        #expect(throws: PreviewFailure.malformedDocument) { try parse(MeshFixtures.threeMF(model: ordinary, relationships: relationships)) }
    }

    @Test func xmlDepthAndNodeCountsComeFromTheBudget() throws {
        let deep = String(repeating: "<x>", count: 100) + String(repeating: "</x>", count: 100)
        #expect(throws: PreviewFailure.structureTooDeep) {
            try parse(package(resources: cubeObject + deep, build: "<item objectid=\"1\"/>"))
        }
        let data = package(resources: cubeObject, build: "<item objectid=\"1\"/>")
        // 28 elements (model, resources, object, mesh, vertices, 8 vertex, triangles, 12 triangle, build, item)
        // plus the default namespace declaration are 29 nodes.
        #expect(MeshFixtures.triangleCount(try parse(data, budget: PreviewBudget(maxInputBytes: 1_000_000, maxJSONNodes: 29))) == 12)
        #expect(throws: PreviewFailure.tooManyNodes) {
            try parse(data, budget: PreviewBudget(maxInputBytes: 1_000_000, maxJSONNodes: 28))
        }
        #expect(throws: PreviewFailure.structureTooDeep) {
            try parse(data, budget: PreviewBudget(maxInputBytes: 1_000_000, maxJSONDepth: 4))
        }
        // Namespace declarations count as nodes too, so thousands of prefixes cannot be used for free.
        let prefixes = (0..<200).map { " xmlns:p\($0)=\"urn:example:\($0)\"" }.joined()
        #expect(throws: PreviewFailure.tooManyNodes) {
            try parse(package(resources: cubeObject, build: "<item objectid=\"1\"/>", namespaces: prefixes))
        }
    }

    // MARK: Budgets

    @Test func enforcesByteAndTriangleBudgets() throws {
        let data = package(resources: cubeObject, build: "<item objectid=\"1\"/>")
        #expect(throws: PreviewFailure.inputTooLarge) { try parse(data, budget: PreviewBudget(maxInputBytes: data.count - 1)) }
        #expect(throws: PreviewFailure.outputTooLarge) {
            try parse(data, budget: PreviewBudget(maxInputBytes: 1_000_000, maxOutputUTF8Bytes: 72 + 143))
        }
        #expect(throws: PreviewFailure.inputTooLarge) {
            try ThreeMFAdapter().parse(FileBytes(data: Data(count: GeometryLimits.maximumInputBytes + 1)), context: MeshFixtures.context)
        }
    }

    @Test func aSmallArchiveCannotInflateBeyondTheDecodedAllowance() throws {
        // Highly compressible padding: tens of kilobytes of XML comment that deflates to a few dozen bytes.
        let padding = "<!--" + String(repeating: "A", count: 400_000) + "-->"
        let model = MeshFixtures.modelXML(resources: cubeObject + padding, build: "<item objectid=\"1\"/>")
        let data = MeshFixtures.threeMF(model: model)
        #expect(data.count < 5_000)
        // 64 times a 4 KiB input allows 256 KiB of decoded model: the 400 KB part is refused up front.
        #expect(throws: PreviewFailure.inputTooLarge) { try parse(data, budget: PreviewBudget(maxInputBytes: 4_096)) }
        #expect(MeshFixtures.triangleCount(try parse(data)) == 12)
    }

    @Test func sourceBytesAreNeverModified() throws {
        let data = package(resources: cubeObject, build: "<item objectid=\"1\"/>")
        let copy = data
        _ = try parse(data)
        #expect(data == copy)
    }
}
