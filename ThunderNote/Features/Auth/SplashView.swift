import SwiftUI

/// Splash：显示品牌标识；登录态判定由 `AuthSession` 完成。
struct SplashView: View {
    var body: some View {
        ZStack {
            DesignTokens.Color.background.ignoresSafeArea()
            VStack(spacing: DesignTokens.Spacing.medium) {
                Image("ic_page_logo_login")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 160)
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
