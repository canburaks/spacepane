import PreviewContracts

// The IGES and STEP format identifiers live with the CAD module, not in PreviewContracts, so a build without CAD carries
// no STEP or IGES identifier (decision 031). The raw values are stored in file-type choices and must not change.
public extension FormatID {
    static let iges = FormatID(rawValue: "cad.iges")
    static let step = FormatID(rawValue: "cad.step")
}
