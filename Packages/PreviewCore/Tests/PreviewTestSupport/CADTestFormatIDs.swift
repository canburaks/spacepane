import PreviewContracts

/// The CAD format identifiers for tests outside the CAD module. The product's own constants live in
/// PreviewCADFormats (decision 031); tests that need a geometry format ID other than a mesh use these.
public enum CADTestFormatIDs {
    public static let iges = FormatID(rawValue: "cad.iges")
    public static let step = FormatID(rawValue: "cad.step")
}
