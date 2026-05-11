import SwiftUI

/// D2-I6-01 / D2-I6-10 我的 tab。
///
/// 当前范围：展示资料（昵称 / 简介 / 头像 emoji / 用户名）+ 服务器 + 关于入口 + 登出。
/// 编辑资料 / 头像裁剪 / 设置页 / 调试日志入口将在 D2-I6 后续推进包接入。
struct ProfileTabView: View {
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var serverConfigStore: ServerConfigStoreObservable
    @StateObject var viewModel: ProfileViewModel

    @State private var toastMessageBridge: String? = nil
    @State private var showAvatarPicker: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    profileHeader
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section("账户") {
                    if case .authenticated(let user) = session.state {
                        LabeledContent("用户名", value: user.username)
                            .accessibilityIdentifier("profileUsernameLabel")
                    } else {
                        LabeledContent("用户名", value: "未登录")
                    }
                    if let bio = viewModel.profile?.bio, !bio.isEmpty {
                        LabeledContent("简介", value: bio)
                            .accessibilityIdentifier("profileBioLabel")
                    }
                }

                Section("服务器") {
                    LabeledContent("当前", value: serverConfigStore.displayLabel)
                        .accessibilityIdentifier("profileServerLabel")
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("关于", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("profileAboutEntry")
                }

                Section {
                    Button(role: .destructive) {
                        Task { await authViewModel.logout() }
                    } label: {
                        Text("退出登录")
                    }
                    .accessibilityIdentifier("profileLogoutButton")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("我的")
            .refreshable { await viewModel.refresh() }
            .task { await viewModel.onAppear() }
            .onChange(of: viewModel.transientMessage) { newValue in
                guard let msg = newValue, !msg.isEmpty else { return }
                ToastCenter.shared.show(key: "Profile:\(msg)", message: msg)
                viewModel.clearTransientMessage()
            }
            .sheet(isPresented: $showAvatarPicker) {
                AvatarEmojiPickerView(initialEmoji: viewModel.profile?.avatar) { emoji in
                    Task { await viewModel.updateAvatar(emoji) }
                }
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            Button {
                showAvatarPicker = true
            } label: {
                Text(resolvedAvatar)
                    .font(.system(size: 48))
                    .frame(width: 64, height: 64)
                    .background(DesignTokens.Color.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profileAvatarLabel")
            .accessibilityHint("点击更换头像 emoji")
            VStack(alignment: .leading, spacing: 4) {
                Text(resolvedNickname)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DesignTokens.Color.textPrimary)
                    .accessibilityIdentifier("profileNicknameLabel")
                if case .authenticated(let user) = session.state {
                    Text("@\(user.username)")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private var resolvedAvatar: String {
        let avatar = viewModel.profile?.avatar
        if let avatar, !avatar.isEmpty, !avatar.hasPrefix("http"), avatar.count <= 4 {
            // emoji 头像直接展示。URL 头像在 D2-I6-04 图片裁剪接入后用 AuthenticatedAsyncImage 渲染。
            return avatar
        }
        return "😊"
    }

    private var resolvedNickname: String {
        if let nickname = viewModel.profile?.nickname, !nickname.isEmpty {
            return nickname
        }
        if case .authenticated(let user) = session.state {
            return user.username
        }
        return "未登录"
    }
}
