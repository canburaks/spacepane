import Foundation
import Security
import PreviewCADFormats

/// launchd owns this independently sandboxed service. Each connection owns its
/// requests; disappearing Quick Look clients cancel their importer children.
final class CADServiceListener: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let requirement = Self.clientRequirement() else { return false }
        connection.setCodeSigningRequirement(requirement)
        let service = CADImportService()
        connection.exportedInterface = CADImportService.interface()
        connection.exportedObject = service
        connection.invalidationHandler = { service.cancelAll() }
        connection.interruptionHandler = { service.cancelAll() }
        connection.resume()
        return true
    }
    /// Restrict the private service to this build's signed preview extension.
    /// Values are build metadata, never source-file values. `CADPeerRequirement` rejects malformed or
    /// unsigned development identities and accepts the team's own signature, a Mac App Store or a TestFlight one;
    /// Security must still parse the result before Foundation sees it.
    private static func clientRequirement() -> String? {
        enum Key {
            static let identifier = "CADAllowedClientIdentifier"
            static let team = "CADAllowedClientTeamIdentifier"
        }
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: Key.identifier) as? String,
              let team = Bundle.main.object(forInfoDictionaryKey: Key.team) as? String,
              let text = CADPeerRequirement.text(identifier: identifier, team: team) else { return nil }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return nil }
        return text
    }
}

let delegate = CADServiceListener()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
