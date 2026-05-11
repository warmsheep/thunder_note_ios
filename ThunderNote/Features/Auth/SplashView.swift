import SwiftUI

/// Splash：显示品牌标识；登录态判定由 `AuthSession` 完成。
struct SplashView: View {
    var body: some View {
        ZStack {
            DesignTokens.Color.background.ignoresSafeArea()
            VStack(spacing: DesignTokens.Spacing.medium) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(DesignTokens.Color.brandPrimary)
                Text("闪记")
                    .font(DesignTokens.Typography.titleLarge)
                    .foregroundStyle(DesignTokens.Color.textPrimary)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(DesignTokens.Color.brandPrimary)
            }
        }
        .accessibilityIdentifier("splashView")
    }
}

#Preview {
    SplashView()
}
