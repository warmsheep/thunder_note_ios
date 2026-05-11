import SwiftUI

/// 与 Android `flashnote_icons` 等价的 emoji chip 选择器。
struct IconChipGrid: View {
    @Binding var selected: String
    var icons: [String] = FlashNoteIcons.all

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(icons, id: \.self) { icon in
                Button {
                    selected = icon
                } label: {
                    Text(icon)
                        .font(.system(size: 28))
                        .frame(width: 44, height: 44)
                        .background(
                            selected == icon
                                ? DesignTokens.Color.brandPrimary.opacity(0.18)
                                : DesignTokens.Color.surface
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.medium)
                                .stroke(
                                    selected == icon ? DesignTokens.Color.brandPrimary : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("iconChip-\(icon)")
            }
        }
    }
}
