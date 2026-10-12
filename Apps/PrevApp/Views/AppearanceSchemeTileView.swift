import SwiftUI
import AppKit
import PreviewRenderers

/// One color scheme as a button: a small swatch drawn from the scheme's own palette colors, and its name. The scheme
/// in use is marked by a thicker ring and a check before its name as well as by the selected trait, so color is never
/// the only sign. No code, file name or file content is drawn: the bars stand in for text.
struct AppearanceSchemeTileView: View {
    let tile: AppearanceSchemeTile
    /// The sentence that says which appearance choosing the tile is for.
    let hint: PreviewStrings.Key
    let choose: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let name = PreviewStrings.text(tile.nameKey)
        Button(action: choose) {
            VStack(spacing: 4) {
                swatch
                label(name)
            }
            .frame(width: AppearanceTileFlow.tileWidth, height: AppearanceTileFlow.tileHeight, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityHint(Text(PreviewStrings.text(hint)))
        .accessibilityAddTraits(tile.isSelected ? .isSelected : [])
    }

    private var swatch: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                bar(tile.keyword, width: 20)
                bar(tile.string, width: 28)
                bar(tile.number, width: 14)
            }
            HStack(spacing: 4) {
                bar(tile.foreground, width: 34)
                bar(tile.comment, width: 22)
            }
        }
        .padding(8)
        .frame(width: AppearanceTileFlow.tileWidth, height: Self.swatchHeight, alignment: .topLeading)
        .background(swatchColor(tile.background), in: shape)
        .overlay(shape.strokeBorder(ring, lineWidth: tile.isSelected ? 3 : 1))
    }

    private func bar(_ rgb: UInt32, width: CGFloat) -> some View {
        Capsule().fill(swatchColor(rgb)).frame(width: width, height: 5)
    }

    private func label(_ name: String) -> some View {
        HStack(spacing: 3) {
            if tile.isSelected {
                Image(systemName: TileSymbol.selected).accessibilityHidden(true)
            }
            Text(verbatim: name)
        }
        .font(tile.isSelected ? CompanionTypography.note.weight(.semibold) : CompanionTypography.note)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .frame(maxWidth: .infinity)
    }

    /// The accent ring marks the scheme in use; with Increase Contrast it is the primary ink, which cannot be lost
    /// against a swatch whatever accent color was chosen in System Settings.
    private var ring: Color {
        if tile.isSelected { return contrast == .increased ? Color.primary : Color.accentColor }
        return Color.primary.opacity(contrast == .increased ? 0.4 : 0.15)
    }

    private static let swatchHeight: CGFloat = 40
}

private enum TileSymbol {
    static let selected = "checkmark"
}

/// A palette color as the renderers store it, 0xRRGGBB, in sRGB.
private func swatchColor(_ rgb: UInt32) -> Color {
    Color(nsColor: NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255, alpha: 1))
}
