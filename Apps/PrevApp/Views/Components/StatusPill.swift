import SwiftUI

/// A compact status with a colored dot. The text states the status on its own.
struct StatusPill: View {
    let text: String
    let tone: CompanionTone

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tone.color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(verbatim: text).font(CompanionTypography.note).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(tone.color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A symbol on a tinted rounded square, used at the leading edge of a banner or link row.
struct SettingsIconBadge: View {
    let image: Image
    let tone: CompanionTone
    var size: CGFloat = 34

    var body: some View {
        image
            .font(.system(size: size * 0.5))
            .foregroundStyle(tone.color)
            .frame(width: size, height: size)
            .background(tone.color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}
