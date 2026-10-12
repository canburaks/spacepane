import SwiftUI
import PreviewContracts
import PreviewRenderers

struct AppearanceSyntaxControls: View {
    @Binding var style: PreviewSyntaxStyle
    @Environment(\.locale) private var locale

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
                                Text(PreviewStrings.text(roleKey(role)))
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
