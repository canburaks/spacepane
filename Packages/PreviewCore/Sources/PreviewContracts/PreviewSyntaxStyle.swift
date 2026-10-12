import Foundation

/// Semantic displayed-text roles, independent of a concrete parser, format or UI framework.
public enum PreviewSyntaxRole: String, Codable, CaseIterable, Sendable {
    case key, string, number, literal, keyword, comment, type, `operator`
    case addition, deletion, heading, tag
}

/// Stable identifiers of the built-in color schemes. They name inert, renderer-owned palettes: a
/// scheme carries no color values, files, fonts or code, so storing or importing one cannot run
/// anything. The raw values are persisted and exchanged and never change with display names.
public enum PreviewColorSchemeID: String, Codable, CaseIterable, Sendable {
    /// The product's own paired light and dark palettes. Valid for either appearance.
    case standard
    case githubLight, solarizedLight, oneLight, paper
    case githubDark, solarizedDark, oneDark, nord, dracula, midnight, aurora

    /// Whether a scheme's own background is light or dark.
    public enum Polarity: String, Codable, CaseIterable, Sendable { case light, dark }

    /// `nil` for Standard, which adapts to both.
    public var polarity: Polarity? {
        switch self {
        case .standard: nil
        case .githubLight, .solarizedLight, .oneLight, .paper: .light
        case .githubDark, .solarizedDark, .oneDark, .nord, .dracula, .midnight, .aurora: .dark
        }
    }

    /// A light preview may only use Standard or a light scheme, and a dark preview Standard or a dark scheme.
    public func isAvailable(for polarity: Polarity) -> Bool {
        self.polarity == nil || self.polarity == polarity
    }

    /// The schemes a picker for one appearance offers, in presentation order, Standard first.
    public static func choices(for polarity: Polarity) -> [PreviewColorSchemeID] {
        allCases.filter { $0.isAvailable(for: polarity) }
    }
}

/// Inert style choices. Renderers own paired, contrast-checked colors and font resolution.
public struct PreviewSyntaxStyle: Codable, Equatable, Sendable {
    public var usesColor: Bool
    public var boldRoles: Set<PreviewSyntaxRole>
    public var italicRoles: Set<PreviewSyntaxRole>
    /// Palette used when the preview is light (explicit Light, or System in a light appearance).
    public var lightScheme: PreviewColorSchemeID
    /// Palette used when the preview is dark. High Contrast and the system Increase Contrast
    /// setting override both choices and use the Standard high-contrast palettes.
    public var darkScheme: PreviewColorSchemeID

    public init(usesColor: Bool = true, boldRoles: Set<PreviewSyntaxRole> = [],
                italicRoles: Set<PreviewSyntaxRole> = [],
                lightScheme: PreviewColorSchemeID = .standard, darkScheme: PreviewColorSchemeID = .standard) {
        self.usesColor = usesColor
        self.boldRoles = boldRoles
        self.italicRoles = italicRoles
        self.lightScheme = lightScheme
        self.darkScheme = darkScheme
    }

    public var isValid: Bool {
        lightScheme.isAvailable(for: .light) && darkScheme.isAvailable(for: .dark)
    }

    private enum CodingKeys: String, CodingKey {
        case usesColor, boldRoles, italicRoles, lightScheme, darkScheme
    }

    /// Current-format decoding is strict: every key must be present. Earlier formats that predate the
    /// scheme fields are read by their own migration types, never by silently defaulting here.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(usesColor: try values.decode(Bool.self, forKey: .usesColor),
                  boldRoles: try values.decode(Set<PreviewSyntaxRole>.self, forKey: .boldRoles),
                  italicRoles: try values.decode(Set<PreviewSyntaxRole>.self, forKey: .italicRoles),
                  lightScheme: try values.decode(PreviewColorSchemeID.self, forKey: .lightScheme),
                  darkScheme: try values.decode(PreviewColorSchemeID.self, forKey: .darkScheme))
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(usesColor, forKey: .usesColor)
        try values.encode(boldRoles, forKey: .boldRoles)
        try values.encode(italicRoles, forKey: .italicRoles)
        try values.encode(lightScheme, forKey: .lightScheme)
        try values.encode(darkScheme, forKey: .darkScheme)
    }
}
