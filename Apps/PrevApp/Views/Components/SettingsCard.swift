import SwiftUI

/// A heading with an optional trailing detail above one or more cards.
struct SettingsSection<Content: View>: View {
    private let title: String
    private let detail: String?
    private let content: Content

    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CompanionMetrics.headingSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: title).font(CompanionTypography.sectionHeading).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let detail {
                    Text(verbatim: detail).font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
                }
            }
            .padding(.horizontal, 2)
            content
        }
    }
}

/// A rounded surface. Direct children become rows separated by hairlines unless
/// `separatesRows` is false.
struct SettingsCard<Content: View>: View {
    private let separatesRows: Bool
    private let content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    init(separatesRows: Bool = true, @ViewBuilder content: () -> Content) {
        self.separatesRows = separatesRows
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if separatesRows {
                Group(subviews: content) { subviews in
                    ForEach(subviews) { subview in
                        if subview.id != subviews.first?.id { Divider() }
                        subview
                    }
                }
            } else {
                content
            }
        }
        .padding(.horizontal, CompanionMetrics.cardPadding)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.4 : 0.09)))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CompanionMetrics.cardCornerRadius, style: .continuous)
    }
}

/// A label, an optional explanation and a trailing control or value.
struct SettingsRow<Control: View>: View {
    private let title: String
    private let subtitle: String?
    private let control: Control

    init(_ title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsRowLabel(title: title, subtitle: subtitle)
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, CompanionMetrics.rowVerticalPadding)
    }
}

extension SettingsRow where Control == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// A row whose trailing control is a switch. VoiceOver reads one element: the
/// switch, labelled by the title and explained by the subtitle.
struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsRowLabel(title: title, subtitle: subtitle).accessibilityHidden(true)
            Spacer(minLength: 8)
            Toggle(isOn: $isOn) { Text(verbatim: title) }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityHint(Text(verbatim: subtitle ?? ""))
        }
        .padding(.vertical, CompanionMetrics.rowVerticalPadding)
    }
}

/// A row whose whole label is the checkbox, so the words on screen are clickable and are what VoiceOver
/// reads. Use it instead of a hidden-label checkbox beside a separate title.
struct SettingsCheckboxRow: View {
    let title: String
    var hint: String?
    @Binding var isOn: Bool

    init(_ title: String, hint: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.hint = hint
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) { Text(verbatim: title) }
            .toggleStyle(.checkbox)
            .accessibilityHint(Text(verbatim: hint ?? ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, CompanionMetrics.rowVerticalPadding)
    }
}

struct SettingsRowLabel: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
            if let subtitle {
                Text(verbatim: subtitle).font(CompanionTypography.note).foregroundStyle(CompanionInk.hint)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
