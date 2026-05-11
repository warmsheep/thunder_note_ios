import SwiftUI

/// D2-I6-10 关于页。
///
/// 与 Android `AboutFragment + fragment_about.xml + strings.xml` 文案一致：
/// - 顶部 App 名「闪记 Thunder Note」
/// - 版本号 `vX.Y.Z`，从 `CFBundleShortVersionString`-`CFBundleVersion` 拼装
/// - slogan「快速记录，灵感闪现 / 让笔记像闪电一样快捷」
/// - GitHub 链接（点击在 Safari 打开，与 D2-I6 验收口径一致）
struct AboutView: View {
    /// GitHub 仓库链接占位。后续切换到真实仓库时改这里。
    static let githubURL = URL(string: "https://github.com/")!

    var body: some View {
        List {
            Section {
                VStack(spacing: DesignTokens.Spacing.medium) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(DesignTokens.Color.brandPrimary)
                        .padding(.top, DesignTokens.Spacing.large)
                        .accessibilityIdentifier("aboutAppIcon")
                    Text("闪记 Thunder Note")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DesignTokens.Color.textPrimary)
                        .accessibilityIdentifier("aboutAppName")
                    Text("版本号 v\(Self.versionLabel())")
                        .font(.system(size: 14))
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                        .accessibilityIdentifier("aboutVersionLabel")
                    Text("快速记录，灵感闪现\n让笔记像闪电一样快捷")
                        .font(.system(size: 14))
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, DesignTokens.Spacing.large)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                Link(destination: Self.githubURL) {
                    HStack {
                        Label("GitHub", systemImage: "link")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(DesignTokens.Color.textSecondary)
                    }
                }
                .accessibilityIdentifier("aboutGithubLink")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 与 Android `BuildConfig.VERSION_NAME` 等价：从 Info.plist 读
    /// `CFBundleShortVersionString`-`CFBundleVersion`，缺省回退「1.0.0」。
    static func versionLabel() -> String {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        let build = (info?["CFBundleVersion"] as? String) ?? ""
        if build.isEmpty || build == short {
            return short
        }
        return "\(short)(\(build))"
    }
}
