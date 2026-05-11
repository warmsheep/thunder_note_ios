import SwiftUI

/// 登录后主壳占位。详细 5 tab 主壳在 D2-I2 阶段实现。
struct MainShellView: View {
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.medium) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(DesignTokens.Color.brandPrimary)
                Text("已登录")
                    .font(DesignTokens.Typography.titleLarge)
                if case .authenticated(let user) = session.state {
                    Text("用户：\(user.username)")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                        .accessibilityIdentifier("mainShellUsername")
                }
                Text("阶段 I-1：网络、认证与会话")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Color.textSecondary)

                Button {
                    Task { await authViewModel.logout() }
                } label: {
                    Text("登出")
                        .font(DesignTokens.Typography.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.white)
                        .background(DesignTokens.Color.brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
                }
                .padding(.horizontal, DesignTokens.Spacing.large)
                .accessibilityIdentifier("mainShellLogoutButton")
            }
            .padding(DesignTokens.Spacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.Color.background.ignoresSafeArea())
            .navigationTitle("闪记")
        }
    }
}
