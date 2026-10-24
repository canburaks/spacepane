import SwiftUI
import PreviewContracts
import PreviewRenderers

struct AppearanceSyntaxControls: View {
    @Binding var style: PreviewSyntaxStyle
    var theme: PreviewTheme = .system
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: NativeTextPalette {
        let isDark = theme == .dark || (theme != .light && colorScheme == .dark)
        let highContrast = theme == .highContrast || contrast == .increased
        return NativeTextPalette(theme: theme, isDark: isDark, increasedContrast: highContrast, style: style)
    }

    var body: some View {
        // The section title, its checkbox and its disclosure each use different words: the title names the
        // group, the checkbox is a visible, clickable label, and the disclosure says what it opens.
        SettingsSection(PreviewStrings.text(.appearanceSyntaxStyles)) {
            SettingsCard {
                SettingsCheckboxRow(PreviewStrings.text(.syntaxUsesColor), isOn: $style.usesColor)
                DisclosureGroup(PreviewStrings.text(.syntaxTraits)) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        ForEach(PreviewSyntaxRole.allCases, id: \.self) { role in
                            GridRow {
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Color(nsColor: style.usesColor ? palette.color(for: role) : palette.foreground))
                                        .frame(width: 10, height: 10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
                                        )
                                        .accessibilityHidden(true)
                                    Text(PreviewStrings.text(roleKey(role)))
                                        .fontWeight(style.boldRoles.contains(role) ? .bold : .regular)
                                        .italic(style.italicRoles.contains(role))
                                }
                                traitToggle(.syntaxBold, role: role, keyPath: \.boldRoles)
                                traitToggle(.syntaxItalic, role: role, keyPath: \.italicRoles)
                            }
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                }
                .padding(.vertical, CompanionMetrics.rowVerticalPadding)
                Text(PreviewStrings.text(.syntaxStylesHint))
                    .font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            }
        }
    }

    private func traitToggle(_ key: PreviewStrings.Key, role: PreviewSyntaxRole,
                             keyPath: WritableKeyPath<PreviewSyntaxStyle, Set<PreviewSyntaxRole>>) -> some View {
        Toggle(PreviewStrings.text(key), isOn: Binding(
            get: { style[keyPath: keyPath].contains(role) },
            set: { enabled in
                if enabled { style[keyPath: keyPath].insert(role) }
                else { style[keyPath: keyPath].remove(role) }
            }))
        .toggleStyle(.checkbox)
        .help(PreviewStrings.format(.syntaxStyleControl,
            arguments: [PreviewStrings.text(roleKey(role)), PreviewStrings.text(key)], locale: locale))
        .accessibilityLabel(Text(PreviewStrings.format(.syntaxStyleControl,
            arguments: [PreviewStrings.text(roleKey(role)), PreviewStrings.text(key)], locale: locale)))
    }

    private func roleKey(_ role: PreviewSyntaxRole) -> PreviewStrings.Key {
        switch role {
        case .key: .syntaxRoleKey
        case .string: .syntaxRoleString
        case .number: .syntaxRoleNumber
        case .literal: .syntaxRoleLiteral
        case .keyword: .syntaxRoleKeyword
        case .comment: .syntaxRoleComment
        case .type: .syntaxRoleType
        case .operator: .syntaxRoleOperator
        case .addition: .syntaxRoleAddition
        case .deletion: .syntaxRoleDeletion
        case .heading: .syntaxRoleHeading
        case .tag: .syntaxRoleTag
        }
    }
}
