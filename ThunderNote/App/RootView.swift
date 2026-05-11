import SwiftUI

/// 顶层路由：根据 `AuthSession.state` 切换 Splash / Login / MainShell。
struct RootView: View {
    @EnvironmentObject private var session: AuthSession

    var body: some View {
        Group {
            switch session.state {
            case .unknown:
                SplashView()
            case .anonymous:
                LoginView()
            case .authenticated:
                MainTabView()
            }
        }
        .accessibilityIdentifier("rootView")
    }
}
