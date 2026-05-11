import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var viewModel: AuthViewModel
    @EnvironmentObject private var serverConfigStore: ServerConfigStoreObservable
    @State private var showRegister = false
    @State private var showServerConfig = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                header
                fields
                actionButton
                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("loginErrorText")
                }
                Spacer(minLength: DesignTokens.Spacing.large)
                serverFooter
            }
            .padding(DesignTokens.Spacing.large)
        }
        .background(DesignTokens.Color.background.ignoresSafeArea())
        .sheet(isPresented: $showRegister) {
            RegisterView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showServerConfig) {
            ServerConfigSheet()
                .environmentObject(serverConfigStore)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(DesignTokens.Color.brandPrimary)
            Text("欢迎使用闪记")
                .font(DesignTokens.Typography.titleLarge)
                .foregroundStyle(DesignTokens.Color.textPrimary)
            Text("登录后开始你的闪记")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
    }

    private var fields: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            TextField("用户名", text: $viewModel.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .padding()
                .background(DesignTokens.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
                .accessibilityIdentifier("loginUsernameField")

            SecureField("密码", text: $viewModel.password)
                .padding()
                .background(DesignTokens.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
                .accessibilityIdentifier("loginPasswordField")
        }
    }

    private var actionButton: some View {
        VStack(spacing: DesignTokens.Spacing.small) {
            Button {
                Task { await viewModel.login() }
            } label: {
                ZStack {
                    if viewModel.isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text("登录")
                            .font(DesignTokens.Typography.body.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(DesignTokens.Color.brandPrimary)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
            }
            .disabled(viewModel.isWorking)
            .accessibilityIdentifier("loginSubmitButton")

            Button("注册新账号") { showRegister = true }
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.brandPrimary)
                .accessibilityIdentifier("loginGoRegisterButton")
        }
    }

    private var serverFooter: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
            Text("当前服务器")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Color.textSecondary)
            HStack {
                Text(serverConfigStore.displayLabel)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Color.textPrimary)
                Spacer()
                Button("切换") { showServerConfig = true }
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Color.brandPrimary)
                    .accessibilityIdentifier("loginSwitchServerButton")
            }
        }
        .padding()
        .background(DesignTokens.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
    }
}
