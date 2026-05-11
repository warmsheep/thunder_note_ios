import SwiftUI

struct RootView: View {
    var body: some View {
        ZStack {
            DesignTokens.Color.background
                .ignoresSafeArea()

            VStack(spacing: DesignTokens.Spacing.medium) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(DesignTokens.Color.brandPrimary)

                Text("闪记")
                    .font(DesignTokens.Typography.titleLarge)
                    .foregroundStyle(DesignTokens.Color.textPrimary)
                    .accessibilityIdentifier("rootBrandTitle")

                Text("阶段 I-0：工程基线")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Color.textSecondary)
            }
            .padding(DesignTokens.Spacing.large)
        }
    }
}

#Preview {
    RootView()
}
