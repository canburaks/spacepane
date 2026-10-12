import Foundation

public enum PreviewTheme: String, Codable, CaseIterable, Sendable {
    case system, light, dark, highContrast
}

public enum PreviewFontWeight: String, Codable, CaseIterable, Sendable {
    case regular, medium, semibold, bold
}

public struct PreviewTypography: Codable, Equatable, Sendable {
    public static let fontSizeRange: ClosedRange<Double> = 8...48
    public static let lineSpacingRange: ClosedRange<Double> = 0...20
    public static let characterSpacingRange: ClosedRange<Double> = -1...10
    public static let tabWidthRange = 1...16
    public static let maximumFontFamilyUTF8Bytes = 128

    public var fontSize: Double
    public var wrapsLines: Bool
    /// nil requests the system monospaced family; renderers resolve unavailable families safely.
    public var fontFamily: String?
    public var weight: PreviewFontWeight
    public var italic: Bool
    public var lineSpacing: Double
    public var characterSpacing: Double
    public var ligatures: Bool
    public var tabWidth: Int
    public var showsLineNumbers: Bool

    public init(fontSize: Double = 13, wrapsLines: Bool = true, fontFamily: String? = nil,
                weight: PreviewFontWeight = .regular, italic: Bool = false, lineSpacing: Double = 0,
                characterSpacing: Double = 0, ligatures: Bool = true, tabWidth: Int = 4,
                showsLineNumbers: Bool = false) {
        self.fontSize = fontSize
        self.wrapsLines = wrapsLines
        self.fontFamily = fontFamily
        self.weight = weight
        self.italic = italic
        self.lineSpacing = lineSpacing
        self.characterSpacing = characterSpacing
        self.ligatures = ligatures
        self.tabWidth = tabWidth
        self.showsLineNumbers = showsLineNumbers
    }

    public var isValid: Bool {
        fontSize.isFinite && Self.fontSizeRange.contains(fontSize)
        && lineSpacing.isFinite && Self.lineSpacingRange.contains(lineSpacing)
        && characterSpacing.isFinite && Self.characterSpacingRange.contains(characterSpacing)
        && Self.tabWidthRange.contains(tabWidth) && hasValidFontFamily
    }

    private var hasValidFontFamily: Bool {
        guard let fontFamily else { return true }
        return !fontFamily.isEmpty && fontFamily.utf8.count <= Self.maximumFontFamilyUTF8Bytes
        && fontFamily == fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        && fontFamily.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil
    }

    private enum CodingKeys: String, CodingKey {
        case fontSize, wrapsLines, fontFamily, weight, italic, lineSpacing, characterSpacing, ligatures, tabWidth
        case showsLineNumbers
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(fontSize: try values.decode(Double.self, forKey: .fontSize),
                  wrapsLines: try values.decode(Bool.self, forKey: .wrapsLines),
                  fontFamily: try values.decode(String?.self, forKey: .fontFamily),
                  weight: try values.decode(PreviewFontWeight.self, forKey: .weight),
                  italic: try values.decode(Bool.self, forKey: .italic),
                  lineSpacing: try values.decode(Double.self, forKey: .lineSpacing),
                  characterSpacing: try values.decode(Double.self, forKey: .characterSpacing),
                  ligatures: try values.decode(Bool.self, forKey: .ligatures),
                  tabWidth: try values.decode(Int.self, forKey: .tabWidth),
                  showsLineNumbers: try values.decode(Bool.self, forKey: .showsLineNumbers))
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(fontSize, forKey: .fontSize)
        try values.encode(wrapsLines, forKey: .wrapsLines)
        // Explicit null distinguishes the valid system default from an incomplete current payload.
        try values.encode(fontFamily, forKey: .fontFamily)
        try values.encode(weight, forKey: .weight)
        try values.encode(italic, forKey: .italic)
        try values.encode(lineSpacing, forKey: .lineSpacing)
        try values.encode(characterSpacing, forKey: .characterSpacing)
        try values.encode(ligatures, forKey: .ligatures)
        try values.encode(tabWidth, forKey: .tabWidth)
        try values.encode(showsLineNumbers, forKey: .showsLineNumbers)
    }
}

public struct PreviewPreferencesSnapshot: Equatable, Sendable {
    public var defaultEnabled: Bool
    public var formatOverrides: [FormatID: Bool]
    public var typography: PreviewTypography
    public var theme: PreviewTheme
    public var syntaxStyle: PreviewSyntaxStyle
    public var appearanceProfiles: [PreviewAppearanceProfile]
    /// Behavior choices shared by the companion and both extensions, persisted since schema 6.
    public var reloadsOnFileChange: Bool
    /// Thumbnails may draw a concealed excerpt only for catalog formats whose policy is `content`.
    public var showsContentThumbnails: Bool
    /// Persisted only within `PreviewRequestOptions.folderDepthRange`; a request still clamps defensively.
    public var folderDepth: Int
    public var showsHiddenFolderItems: Bool

    public init(defaultEnabled: Bool = true, formatOverrides: [FormatID: Bool] = [:],
                typography: PreviewTypography = PreviewTypography(), theme: PreviewTheme = .system,
                syntaxStyle: PreviewSyntaxStyle = PreviewSyntaxStyle(),
                appearanceProfiles: [PreviewAppearanceProfile] = [],
                reloadsOnFileChange: Bool = true, showsContentThumbnails: Bool = true,
                folderDepth: Int = 1, showsHiddenFolderItems: Bool = false) {
        self.defaultEnabled = defaultEnabled
        self.formatOverrides = formatOverrides
        self.typography = typography
        self.theme = theme
        self.syntaxStyle = syntaxStyle
        self.appearanceProfiles = appearanceProfiles
        self.reloadsOnFileChange = reloadsOnFileChange
        self.showsContentThumbnails = showsContentThumbnails
        self.folderDepth = folderDepth
        self.showsHiddenFolderItems = showsHiddenFolderItems
    }

    /// The only path by which preferences reach adapters.
    public var requestOptions: PreviewRequestOptions {
        PreviewRequestOptions(folderDepth: folderDepth, includesHiddenItems: showsHiddenFolderItems)
    }

    public static let defaults = PreviewPreferencesSnapshot()
    public static let disabledContentFallback = PreviewPreferencesSnapshot(defaultEnabled: false)
    public func isEnabled(_ id: FormatID, catalog: FormatCatalog = .standard) -> Bool {
        formatOverrides[id] ?? inheritedEnablement(for: id, catalog: catalog)
    }
    public mutating func setEnabled(_ enabled: Bool, for id: FormatID, catalog: FormatCatalog = .standard) {
        formatOverrides[id] = enabled == inheritedEnablement(for: id, catalog: catalog) ? nil : enabled
    }
    public mutating func setAllEnabled(_ enabled: Bool, catalog: FormatCatalog = .standard) {
        defaultEnabled = enabled
        formatOverrides.removeAll()
        if enabled {
            // An explicit bulk action opts into only the expensive types present today.
            // New opt-in types do not inherit consent from an earlier Enable All action.
            for descriptor in catalog.descriptors where !descriptor.defaultEnabled {
                formatOverrides[descriptor.id] = true
            }
        }
    }
    public mutating func resetFileTypeChoices() {
        defaultEnabled = true
        formatOverrides.removeAll()
    }
    private func inheritedEnablement(for id: FormatID, catalog: FormatCatalog) -> Bool {
        defaultEnabled && (catalog.descriptor(for: id)?.defaultEnabled ?? true)
    }
    public mutating func resetAppearance() {
        typography = PreviewTypography()
        theme = .system
        syntaxStyle = PreviewSyntaxStyle()
    }

    public var appearance: PreviewAppearance {
        get { PreviewAppearance(typography: typography, theme: theme, syntaxStyle: syntaxStyle) }
        set { typography = newValue.typography; theme = newValue.theme; syntaxStyle = newValue.syntaxStyle }
    }

    public var hasValidAppearance: Bool {
        appearance.isValid && appearanceProfiles.count <= PreviewAppearanceProfile.maximumCount
        && appearanceProfiles.allSatisfy(\.isValid)
        && Set(appearanceProfiles.map(\.id)).count == appearanceProfiles.count
    }

    /// The behavior fields have finite bounds; an out-of-range stored depth is corrupt, not clamped.
    public var hasValidBehavior: Bool {
        PreviewRequestOptions.folderDepthRange.contains(folderDepth)
    }

    /// Everything the store accepts besides file-type identifiers, which it validates itself.
    public var hasValidChoices: Bool { hasValidAppearance && hasValidBehavior }
}
