import SwiftUI

/// 我的 tab：当前最小可用版本——展示当前用户名 + 登出。
/// 完整资料 / 设置 / 同步等能力在 D2-I6 阶段接入。
struct ProfileTabView: View {
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var serverConfigStore: ServerConfigStoreObservable

    var body: some View {
        NavigationStack {
            List {
                Section("账户") {
                    if case .authenticated(let user) = session.state {
                        LabeledContent("用户名", value: user.username)
                            .accessibilityIdentifier("profileUsernameLabel")
                    } else {
                        LabeledContent("用户名", value: "未登录")
                    }
                }

                Section("服务器") {
                    LabeledContent("当前", value: serverConfigStore.displayLabel)
                        .accessibilityIdentifier("profileServerLabel")
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
        }
    }
}
