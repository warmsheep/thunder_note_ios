import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var viewModel: AuthViewModel
    @EnvironmentObject private var serverConfigStore: ServerConfigStoreObservable
    @State private var showRegister = false
    @State private var showServerConfig = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Image("ic_page_logo_login")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 160, height: 160)

                    Text("欢迎回来")
                        .font(DesignTokens.Typography.titleLarge)
                        .foregroundStyle(DesignTokens.Color.textPrimary)
                        .padding(.top, 30)

                    Text("登录以继续使用闪记")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                        .padding(.top, 8)

                    TextField("请输入用户名", text: $viewModel.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(DesignTokens.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
                        .padding(.top, 40)
                        .accessibilityIdentifier("loginUsernameField")

                    SecureField("请输入密码", text: $viewModel.password)
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(DesignTokens.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
                        .padding(.top, 16)
                        .accessibilityIdentifier("loginPasswordField")

                    Button {
                        Task { await viewModel.login() }
                    } label: {
                        ZStack {
                            if viewModel.isWorking {
                                ProgressView().tint(.white)
                            } else {
                                Text("登录")
                                    .font(DesignTokens.Typography.body.weight(.bold))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(.white)
                        .background(DesignTokens.Color.brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
                    }
                    .disabled(viewModel.isWorking)
                    .padding(.top, 18)
                    .accessibilityIdentifier("loginSubmitButton")

                    if let message = viewModel.errorMessage {
                        Text(message)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Color.danger)
                            .padding(.top, 10)
                            .accessibilityIdentifier("loginErrorText")
                    }

                    Button("还没有账号？立即注册") {
                        showRegister = true
                    }
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Color.brandPrimary)
                    .padding(.top, 14)
                    .accessibilityIdentifier("loginGoRegisterButton")

                    Spacer(minLength: 0)

                    Button {
                        showServerConfig = true
                    } label: {
                        Text(serverConfigStore.displayLabel + "  ›")
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(DesignTokens.Color.brandPrimary)
                    }
                    .padding(.top, 20)
                    .accessibilityIdentifier("loginSwitchServerButton")
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .padding(.bottom, 20)
                .frame(minHeight: geometry.size.height)
            }
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
}
