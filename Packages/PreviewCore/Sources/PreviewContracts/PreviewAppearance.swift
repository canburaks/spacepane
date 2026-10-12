import Foundation

/// Transferable appearance excludes file policy and user preview contents.
public struct PreviewAppearance: Codable, Equatable, Sendable {
    public var typography: PreviewTypography
    public var theme: PreviewTheme
    public var syntaxStyle: PreviewSyntaxStyle

    public init(typography: PreviewTypography = PreviewTypography(), theme: PreviewTheme = .system,
                syntaxStyle: PreviewSyntaxStyle = PreviewSyntaxStyle()) {
        self.typography = typography
        self.theme = theme
        self.syntaxStyle = syntaxStyle
    }

    public var isValid: Bool { typography.isValid && syntaxStyle.isValid }
}

public struct PreviewAppearanceProfile: Codable, Equatable, Sendable, Identifiable {
    public static let maximumCount = 32
    public static let maximumNameUTF8Bytes = 128
    public let id: UUID
    public var name: String
    public var appearance: PreviewAppearance

    public init(id: UUID = UUID(), name: String, appearance: PreviewAppearance) {
        self.id = id
        self.name = name
        self.appearance = appearance
    }

    public var isValid: Bool { Self.isValidName(name) && appearance.isValid }

    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= maximumNameUTF8Bytes
        && name == name.trimmingCharacters(in: .whitespacesAndNewlines)
        && name.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil
        && !name.unicodeScalars.contains(where: { (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value) })
    }
}
