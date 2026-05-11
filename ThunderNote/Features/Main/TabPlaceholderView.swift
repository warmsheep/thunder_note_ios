import SwiftUI

/// 占位 tab 视图：4 个非 MVP 优先的 tab 共用，凸显「该模块尚未接入」。
struct TabPlaceholderView: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.medium) {
                Image(systemName: icon)
                    .font(.system(size: 56))
                    .foregroundStyle(DesignTokens.Color.brandPrimary.opacity(0.85))
                Text(title)
                    .font(DesignTokens.Typography.titleLarge)
                Text(description)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignTokens.Spacing.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.Color.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("tabPlaceholder-\(title)")
    }
}
