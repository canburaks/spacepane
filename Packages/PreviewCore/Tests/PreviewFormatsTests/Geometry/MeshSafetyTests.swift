import Foundation
import Testing
import UniformTypeIdentifiers
import PreviewContracts
import PreviewFormats

@Suite("Mesh adapter safety")
struct MeshSafetyTests {
    private let torus = MeshFixtures.torus(segments: 120, sides: 60)   // 7,200 vertices, 14,400 triangles

    /// One valid file per registered format, built from the same torus.
    private var samples: [(FormatID, Data)] {
        let triangles = MeshFixtures.triangles(torus.quads)
        return [(.meshSTL, MeshFixtures.stlBinary(torus.vertices, triangles)),
                (.meshOBJ, MeshFixtures.obj(torus.vertices, faces: torus.quads)),
                (.meshPLY, MeshFixtures.plyBinary(torus.vertices, faces: torus.quads)),
                (.mesh3MF, MeshFixtures.threeMF(vertices: torus.vertices, triangles: triangles))]
    }

    private func adapter(for id: FormatID) throws -> any GeometryFormatAdapter {
        let registration = try #require(MeshFormatAdapters.registrations.first { $0.formatID == id })
        guard case .geometry(let make) = registration.inputPath else {
            Issue.record("\(id.rawValue) must use the geometry input path")
            throw PreviewFailure.unsupportedFormat
        }
        return make()
    }

    @Test func everyMeshFormatIsRegisteredOnceWithTheMeshBudget() throws {
        let ids = MeshFormatAdapters.registrations.map(\.formatID)
        #expect(ids == [.meshSTL, .meshOBJ, .meshPLY, .mesh3MF])
        #expect(Set(ids).count == ids.count)
        for registration in MeshFormatAdapters.registrations {
            #expect(registration.defaultBudget == MeshLimits.requestBudget)
            #expect(registration.sourcePolicy == .regularFile)
        }
        #expect(MeshLimits.requestBudget.isValid)
        // The adapters are part of the standard set every host composes.
        let standard = Set(StandardFormatAdapters.registrations.map(\.formatID))
        for id in ids { #expect(standard.contains(id)) }
    }

    @Test func everyAdapterChecksCancellationBeforeTouchingInput() async throws {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            for registration in MeshFormatAdapters.registrations {
                guard case .geometry(let make) = registration.inputPath else { continue }
                // Valid bytes would parse; only cancellation can explain a CancellationError.
                #expect(throws: CancellationError.self, "\(registration.formatID.rawValue)") {
                    try make().parse(FileBytes(data: Data()), context: RequestContext(budget: MeshLimits.requestBudget))
                }
            }
        }
        await task.value
    }

    @Test func everyAdapterChecksAnExpiredDeadlineBeforeTouchingInput() throws {
        for (id, data) in samples {
            #expect(throws: PreviewFailure.deadlineExceeded, "\(id.rawValue)") {
                try adapter(for: id).parse(FileBytes(data: data), context: RequestContext(budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 0)))
            }
        }
    }

    @Test func aDeadlineThatPassesWhileParsingStopsTheWork() throws {
        // A larger model than the others so that the one-millisecond deadline expires inside the loops.
        let big = MeshFixtures.torus(segments: 400, sides: 100)
        let triangles = MeshFixtures.triangles(big.quads)
        let inputs: [(FormatID, Data)] = [
            (.meshSTL, MeshFixtures.stlBinary(big.vertices, triangles)),
            (.meshOBJ, MeshFixtures.obj(big.vertices, faces: big.quads)),
            (.meshPLY, MeshFixtures.plyBinary(big.vertices, faces: big.quads)),
            (.mesh3MF, MeshFixtures.threeMF(vertices: big.vertices, triangles: triangles))]
        for (id, data) in inputs {
            #expect(throws: PreviewFailure.deadlineExceeded, "\(id.rawValue)") {
                try adapter(for: id).parse(FileBytes(data: data), context: RequestContext(budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 1)))
            }
        }
    }

    @Test func cancellingAnInFlightParseThrowsCancellationAndNothingElse() async throws {
        let big = MeshFixtures.torus(segments: 400, sides: 100)
        let data = MeshFixtures.obj(big.vertices, faces: big.quads)
        let parser = try adapter(for: .meshOBJ)
        let task = Task.detached { () -> Bool in
            do {
                _ = try parser.parse(FileBytes(data: data), context: RequestContext(budget: MeshLimits.requestBudget))
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }
        // Cancelled while the reader runs (or before it starts): the answer is a cancellation either way.
        task.cancel()
        #expect(await task.value)
    }

    @Test func adaptersAreStatelessAndRepeatable() throws {
        for (id, data) in samples {
            let reader = try adapter(for: id)
            let first = try reader.parse(FileBytes(data: data), context: MeshFixtures.context)
            let second = try reader.parse(FileBytes(data: data), context: MeshFixtures.context)
            #expect(first == second, "\(id.rawValue)")
            MeshFixtures.expectWellFormed(first)
            #expect(MeshFixtures.triangleCount(first) == 14_400, "\(id.rawValue)")
        }
    }

    @Test func truncatedAndMutatedFilesNeverCrashAndFailWithTypedErrors() throws {
        var generator = SplitMix64(seed: 0x4D455348)
        for (id, data) in samples {
            let reader = try adapter(for: id)
            var cases: [Data] = [Data(), data.prefix(1), data.prefix(data.count / 3), data.prefix(data.count - 1),
                                 Data(repeating: 0xFF, count: 64) + data, Data(repeating: 0, count: 4_096)]
            for _ in 0..<12 {
                var mutated = data
                for _ in 0..<8 { mutated[Int(generator.next() % UInt64(mutated.count))] = UInt8(truncatingIfNeeded: generator.next()) }
                cases.append(mutated)
            }
            for candidate in cases {
                do {
                    let mesh = try reader.parse(FileBytes(data: candidate), context: MeshFixtures.context)
                    MeshFixtures.expectWellFormed(mesh)
                } catch is PreviewFailure {
                    // A typed failure is the contract.
                } catch {
                    Issue.record("\(id.rawValue): untyped error \(error)")
                }
            }
        }
    }
}

/// Small deterministic generator so the mutation cases are the same on every run.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Suite("Mesh catalog entries")
struct MeshCatalogTests {
    private let expectations: [(id: FormatID, suffix: String, systemType: String?)] = [
        (.meshSTL, "stl", "public.standard-tesselated-geometry-format"),
        (.meshOBJ, "obj", "public.geometry-definition-format"),
        (.meshPLY, "ply", "public.polygon-file-format"),
        (.mesh3MF, "3mf", nil)]

    @Test func stableIdentifiersAreTheDocumentedOnes() {
        #expect(FormatID.meshSTL.rawValue == "model.stl")
        #expect(FormatID.meshOBJ.rawValue == "model.obj")
        #expect(FormatID.meshPLY.rawValue == "model.ply")
        #expect(FormatID.mesh3MF.rawValue == "model.3mf")
    }

    @Test func entriesUseGeometryMediaAndLeaveSystemThumbnailsInPlaceAndAreOnByDefault() throws {
        for expected in expectations {
            let descriptor = try #require(FormatCatalog.standard.descriptor(for: expected.id))
            #expect(descriptor.group == .media)
            #expect(descriptor.presentation == .geometry)
            // macOS draws real thumbnails for the system mesh types; only 3MF, which has none, gets the glyph.
            #expect(descriptor.thumbnail == (expected.id == .mesh3MF ? .generic : .none))
            #expect(descriptor.defaultEnabled)
            #expect(descriptor.suffixAliases == [expected.suffix])
            #expect(descriptor.nameKey == "format.\(expected.id.rawValue).name")
            #expect(descriptor.descriptionKey == "format.\(expected.id.rawValue).description")
            #expect(PreviewPreferencesSnapshot.defaults.isEnabled(expected.id, catalog: .standard))
        }
    }

    @Test func systemTypesAreUsedWhereTheyExistAndOnlyThe3MFTypeIsImported() throws {
        for expected in expectations {
            let descriptor = try #require(FormatCatalog.standard.descriptor(for: expected.id))
            if let system = expected.systemType {
                #expect(descriptor.contentTypes.map(\.identifier) == [system])
                #expect(!descriptor.canonicalContentType.isDynamic)
            } else {
                #expect(descriptor.canonicalContentType.identifier == "org.webmeister.spacepane.type.3mf")
                #expect(!descriptor.canonicalContentType.conforms(to: .plainText))
            }
        }
    }

    @Test(arguments: ["stl", "STL", "obj", "OBJ", "ply", "PLY", "3mf", "3MF"])
    func suffixesWinOverTextFallbackEvenForTextTypedFiles(suffix: String) {
        // An OBJ file conforms to public.text; the suffix still routes it to the mesh viewer, so the
        // file-type switch governs it and disabling it never falls back to generic text.
        let url = URL(fileURLWithPath: "/unused/model.\(suffix)")
        let expected = expectations.first { $0.suffix == suffix.lowercased() }?.id
        #expect(FormatCatalog.standard.classify(url: url, contentType: .plainText) == expected)
        #expect(FormatCatalog.standard.classify(url: url, contentType: .data) == expected)
        #expect(FormatCatalog.standard.classify(url: url) == expected)
    }

    @Test func declaredTypesClassifyWithoutASuffixAndNeverCaptureOtherData() throws {
        for expected in expectations {
            let descriptor = try #require(FormatCatalog.standard.descriptor(for: expected.id))
            #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/unused/model"), contentType: descriptor.canonicalContentType) == expected.id)
        }
        // Another suffix with generic content never reaches a mesh format.
        #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/unused/model.bin"), contentType: .data) == nil)
    }

    @Test func eachFormatCanBeDisabledIndependently() {
        for expected in expectations {
            var snapshot = PreviewPreferencesSnapshot.defaults
            snapshot.setEnabled(false, for: expected.id)
            #expect(!snapshot.isEnabled(expected.id, catalog: .standard))
            for other in expectations where other.id != expected.id {
                #expect(snapshot.isEnabled(other.id, catalog: .standard))
            }
        }
    }
}
