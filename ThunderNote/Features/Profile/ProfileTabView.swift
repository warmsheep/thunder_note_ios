import SwiftUI
import UIKit

/// D2-I6 我的 tab。
///
/// - D2-I6-01 资料展示（cached + refresh）
/// - D2-I6-06 顶部主色渐变头部（与 Android `bg_profile_header` 等价）
/// - D2-I6-08 三联统计（闪记 / 收藏 / 记录数）
/// - D2-I6-09 设置入口（NavigationLink → `SettingsView`）
/// - D2-I6-05 头像 / 昵称 tap → 编辑资料独立页
/// - D2-I6-10 关于入口由「设置 → 关于」二级页面提供
struct ProfileTabView: View {
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var serverConfigStore: ServerConfigStoreObservable
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject var viewModel: ProfileViewModel
    @StateObject var statsViewModel: ProfileStatsViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    gradientHeader
                    statsRow
                        .padding(.horizontal, DesignTokens.Spacing.medium)
                        .padding(.top, DesignTokens.Spacing.medium)
                    actionList
                        .padding(.horizontal, DesignTokens.Spacing.medium)
                        .padding(.top, DesignTokens.Spacing.medium)
                    Spacer(minLength: 24)
                }
            }
            .background(DesignTokens.Color.background.ignoresSafeArea())
            .refreshable {
                await viewModel.refresh()
                await statsViewModel.refresh()
            }
            .task {
                await viewModel.onAppear()
                await statsViewModel.refresh()
            }
            .onChange(of: viewModel.transientMessage) { newValue in
                guard let msg = newValue, !msg.isEmpty else { return }
                ToastCenter.shared.show(key: "Profile:\(msg)", message: msg)
                viewModel.clearTransientMessage()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - 头部渐变

    private var gradientHeader: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [DesignTokens.Color.brandPrimary, DesignTokens.Color.brandSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 220)
            .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.medium) {
                    NavigationLink {
                        EditProfileView(viewModel: viewModel)
                            .environmentObject(dependencies)
                    } label: {
                        avatarPreview
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))
                            .accessibilityIdentifier("profileAvatarLabel")
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(resolvedNickname)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .accessibilityIdentifier("profileNicknameLabel")
                        if case .authenticated(let user) = session.state {
                            Text("@\(user.username)")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .accessibilityIdentifier("profileUsernameLabel")
                        }
                        if let bio = viewModel.profile?.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.9))
                                .lineLimit(2)
                                .accessibilityIdentifier("profileBioLabel")
                        }
                    }
                    Spacer()
                }
                .padding(.top, 56)
                .padding(.horizontal, DesignTokens.Spacing.large)

                NavigationLink {
                    EditProfileView(viewModel: viewModel)
                        .environmentObject(dependencies)
                } label: {
                    Text("编辑资料")
                        .font(.system(size: 13))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.22))
                        .foregroundStyle(Color.white)
                        .clipShape(Capsule())
                }
                .padding(.leading, DesignTokens.Spacing.large)
                .padding(.bottom, 16)
                .accessibilityIdentifier("profileEditEntry")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 220)
    }

    @ViewBuilder
    private var avatarPreview: some View {
        let avatar = viewModel.profile?.avatar
        if let avatar, isEmoji(avatar) {
            Text(avatar)
                .font(.system(size: 44))
                .frame(width: 72, height: 72)
                .background(Color.white.opacity(0.15))
        } else if let local = AvatarLocalCache.loadImage() {
            Image(uiImage: local)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
        } else if let avatar,
                  let url = dependencies.mediaUrlResolver.resolve(avatar) {
            AuthenticatedAsyncImage(
                url: url,
                loader: dependencies.authenticatedImageLoader,
                content: { image in
                    image.resizable().scaledToFill()
                },
                placeholder: {
                    Text("😊").font(.system(size: 44))
                }
            )
            .frame(width: 72, height: 72)
        } else {
            Text("😊")
                .font(.system(size: 44))
                .frame(width: 72, height: 72)
                .background(Color.white.opacity(0.15))
        }
    }

    private func isEmoji(_ avatar: String) -> Bool {
        !avatar.isEmpty && !avatar.hasPrefix("http") && !avatar.contains("/") && avatar.count <= 4
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

    // MARK: - 统计行

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(value: "\(statsViewModel.stats.flashNoteCount)", label: "闪记", id: "profileStatFlashNote")
            divider
            statCell(value: "\(statsViewModel.stats.favoriteCount)", label: "收藏", id: "profileStatFavorite")
            divider
            statCell(value: formattedRecord(statsViewModel.stats.recordCount), label: "记录", id: "profileStatRecord")
        }
        .padding(.vertical, 16)
        .background(DesignTokens.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.large))
    }

    private func statCell(value: String, label: String, id: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DesignTokens.Color.textPrimary)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(id)
    }

    private var divider: some View {
        Rectangle()
            .fill(DesignTokens.Color.divider)
            .frame(width: 1, height: 28)
    }

    /// 与 Android `ProfileOpsHelper` 格式化策略保持一致：>=10000 时压缩到 "x.y万"。
    private func formattedRecord(_ count: Int64) -> String {
        if count < 10_000 {
            return "\(count)"
        }
        let value = Double(count) / 10_000.0
        return String(format: "%.1f万", value)
    }

    // MARK: - 设置 / 服务器 / 登出

    private var actionList: some View {
        VStack(spacing: 0) {
            NavigationLink {
                SettingsView()
            } label: {
                listRow(systemImage: "gearshape", title: "设置")
            }
            .accessibilityIdentifier("profileSettingsEntry")

            divider16

            HStack {
                Label("服务器", systemImage: "network")
                    .foregroundStyle(DesignTokens.Color.textPrimary)
                Spacer()
                Text(serverConfigStore.displayLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.Color.textSecondary)
                    .accessibilityIdentifier("profileServerLabel")
            }
            .padding(.horizontal, 16)
            .frame(height: 48)

            divider16

            Button(role: .destructive) {
                Task { await authViewModel.logout() }
            } label: {
                HStack {
                    Label("退出登录", systemImage: "arrow.right.square")
                        .foregroundStyle(Color.red)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
            }
            .accessibilityIdentifier("profileLogoutButton")
        }
        .background(DesignTokens.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.large))
    }

    private func listRow(systemImage: String, title: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(DesignTokens.Color.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .contentShape(Rectangle())
    }

    private var divider16: some View {
        Rectangle()
            .fill(DesignTokens.Color.divider)
            .frame(height: 0.5)
            .padding(.leading, 48)
    }
}
