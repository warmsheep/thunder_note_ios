import SwiftUI

struct FavoriteRowView: View {
    let item: FavoriteItem

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            Text(item.displayIcon)
                .font(.system(size: 28))
                .frame(width: 44, height: 44)
                .background(DesignTokens.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .foregroundStyle(DesignTokens.Color.textPrimary)
                    .lineLimit(1)
                Text(item.displayPreview)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("favoriteRow-\(item.id)")
    }
}
