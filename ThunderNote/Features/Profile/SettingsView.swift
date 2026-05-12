import SwiftUI

/// D2-I6-09 设置页骨架。
///
/// 与 Android `SettingsFragment` 对齐的行为列表入口：
/// - 修改密码（D2-I1-06，未来接 ChangePasswordView，当前占位）
/// - 手势锁（D2-I6-16 / 17，未来接 GestureLockSettingsView，当前占位）
/// - 待同步（D2-I7-09，未来接 PendingSyncListView，当前占位）
/// - 关于（D2-I6-10 已落地 → `AboutView`）
/// - 调试日志（D2-I6-15，未来接 `DebugLogView`，当前占位）
struct SettingsView: View {
    var body: some View {
        List {
            Section("账户安全") {
                NavigationLink {
                    PlaceholderSettingsView(title: "修改密码", subtitle: "D2-I1-06 待落地")
                } label: {
                    Label("修改密码", systemImage: "lock.rotation")
                }
                .accessibilityIdentifier("settingsChangePassword")
                NavigationLink {
                    GestureLockSettingsView()
                } label: {
                    Label("手势锁", systemImage: "hand.draw")
                }
                .accessibilityIdentifier("settingsGestureLock")
            }

            Section("同步") {
                NavigationLink {
                    PlaceholderSettingsView(title: "待同步", subtitle: "D2-I7-09 待落地")
                } label: {
                    Label("待同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("settingsPendingSync")
            }

            Section("应用") {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("关于", systemImage: "info.circle")
                }
                .accessibilityIdentifier("settingsAbout")
                NavigationLink {
                    PlaceholderSettingsView(title: "调试日志", subtitle: "D2-I6-13~15 待落地")
                } label: {
                    Label("调试日志", systemImage: "doc.text.magnifyingglass")
                }
                .accessibilityIdentifier("settingsDebugLog")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 设置页二级入口的占位实现，给未来 D2-I6 / D2-I7 / D2-I1 子任务接入留口。
private struct PlaceholderSettingsView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer")
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.Color.textSecondary)
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
