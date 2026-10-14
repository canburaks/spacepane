import Foundation
import PreviewContracts

/// Counts the native-code members of a package for `artifact.nativeCode` (decision 030). Every regular
/// member is checked by name; only the first `maximumMagicChecks` members that the name did not settle
/// are checked by their leading bytes, so a package with a great many files costs a bounded amount of
/// reading. The checks themselves are `NativeCodeSignature`'s, shared with the add-on and model adapters.
struct NativeCodeTally {
    static let maximumMagicChecks = 4_096

    private(set) var count = 0
    private var magicChecks = 0

    /// Whether another member may still be checked by its leading bytes.
    var canCheckMagic: Bool { magicChecks < Self.maximumMagicChecks }

    /// Adds one regular member. `prefix` supplies its leading bytes and is called only when the name
    /// alone does not decide and the budget of magic checks allows it; `nil` means they cannot be read.
    mutating func add(path: String, prefix: () throws -> Data?) rethrows {
        if NativeCodeSignature.hasNativeSuffix(path) {
            count += 1
            return
        }
        guard canCheckMagic else { return }
        magicChecks += 1
        if let bytes = try prefix(), NativeCodeSignature.isNativeBinary(prefix: bytes) { count += 1 }
    }

    /// The finding for the members counted, at the contract's `info` level for packages: shipping a
    /// compiled library is ordinary for many packages and says nothing about intent.
    var finding: PreviewFinding? {
        count > 0 ? PreviewFinding(kind: .artifactNativeCode, severity: .info, count: count) : nil
    }
}
