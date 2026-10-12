import Foundation
import PreviewContracts

public enum CADFormatAdapters {
    private static let serviceIdentifierKey = "CADImportServiceIdentifier"
    public static var registrations: [AdapterRegistration] {
        registrations(workerURL: CADWorkerProcess.bundledExecutableURL)
    }
    /// Explicit injection supports a signed helper in each host and isolated integration tests.
    public static func registrations(workerURL: URL) -> [AdapterRegistration] {
        CADFileKind.allCases.map { kind in
            AdapterRegistration(formatID: kind.formatID, defaultBudget: GeometryLimits.requestBudget) {
                CADFormatAdapter(kind: kind, transport: .worker(workerURL))
            }
        }
    }
    /// Finder extensions use their configured, embedded XPC service. Missing
    /// configuration remains an explicit failure and never launches a direct helper.
    public static var xpcRegistrations: [AdapterRegistration] {
        registrations(serviceName: Bundle.main.object(forInfoDictionaryKey: serviceIdentifierKey) as? String ?? "")
    }
    public static func registrations(serviceName: String) -> [AdapterRegistration] {
        CADFileKind.allCases.map { kind in
            AdapterRegistration(formatID: kind.formatID, defaultBudget: GeometryLimits.requestBudget) {
                CADFormatAdapter(kind: kind, transport: .xpc(serviceName))
            }
        }
    }
}

enum CADFileKind: String, CaseIterable, Sendable {
    case iges, step
    var formatID: FormatID { self == .iges ? .iges : .step }
}

struct CADFormatAdapter: GeometryFormatAdapter {
    let kind: CADFileKind
    enum Transport: Sendable { case worker(URL), xpc(String) }
    let transport: Transport
    func parse(_ input: FileBytes, context: RequestContext) throws -> PreviewMesh {
        guard input.data.count <= min(context.budget.maxInputBytes, GeometryLimits.maximumInputBytes) else {
            throw PreviewFailure.inputTooLarge
        }
        let data: Data
        switch transport {
        case .worker(let workerURL):
            data = try CADWorkerProcess.run(executable: workerURL, arguments: [kind.rawValue], input: input.data, context: context)
        case .xpc(let serviceName):
            data = try CADXPCClient.run(serviceName: serviceName, kind: kind, input: input.data, context: context)
        }
        let mesh = try CADMeshDecoder.decode(data, context: context)
        // Both additions are derived locally after import. Measurements propagate cancellation and the
        // request deadline; unreadable or unknown header facts are simply omitted.
        let measurements = try GeometryMeasurer.measure(mesh, context: context)
        let headerFacts = CADHeaderReader.facts(kind: kind, data: input.data)
        // The importer reports the unit the file declared when it knows it; an IGES header can say it when the importer does not.
        let provenance = CADUnitProvenance.resolve(reported: mesh.unitProvenance, kind: kind, headerFacts: headerFacts)
        return mesh.attaching(measurements: measurements?.declaring(unitProvenance: provenance), headerFacts: headerFacts,
                              unitProvenance: provenance)
    }
}
