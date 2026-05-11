import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var didRegister = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.Spacing.medium) {
                    TextField("用户名（3-32 字符）", text: $viewModel.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding()
                        .background(DesignTokens.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
                        .accessibilityIdentifier("registerUsernameField")

                    TextField("邮箱", text: $viewModel.registerEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding()
                        .background(DesignTokens.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
                        .accessibilityIdentifier("registerEmailField")

                    SecureField("密码（6-128 字符）", text: $viewModel.password)
                        .padding()
                        .background(DesignTokens.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
                        .accessibilityIdentifier("registerPasswordField")

                    if let message = viewModel.errorMessage {
                        Text(message)
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("registerErrorText")
                    }

                    Button {
                        Task {
                            let ok = await viewModel.register()
                            if ok {
                                didRegister = true
                                dismiss()
                            }
                        }
                    } label: {
                        ZStack {
                            if viewModel.isWorking {
                                ProgressView().tint(.white)
                            } else {
                                Text("注册")
                                    .font(DesignTokens.Typography.body.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white)
                        .background(DesignTokens.Color.brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
                    }
                    .disabled(viewModel.isWorking)
                    .accessibilityIdentifier("registerSubmitButton")
                }
                .padding(DesignTokens.Spacing.large)
            }
            .background(DesignTokens.Color.background.ignoresSafeArea())
            .navigationTitle("注册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
