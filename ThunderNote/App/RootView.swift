import SwiftUI

/// 顶层路由：根据 `AuthSession.state` 切换 Splash / Login / MainShell。
/// D2-I6-17: 并在此处覆盖手势解锁页。
struct RootView: View {
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var dependencies: AppDependencies
    @ObservedObject private var lockManager = GestureLockManager.shared

    var body: some View {
        ZStack {
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
            
            // D2-I6-17 手势解锁全屏覆盖
            if lockManager.isLocked, case .authenticated(let user) = session.state {
                GestureLockUnlockOverlay(username: user.username)
            }
        }
    }
}

@MainActor
private struct GestureLockUnlockOverlay: View {
    let username: String
    @EnvironmentObject private var dependencies: AppDependencies
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            
            GestureLockVerifyView(username: username, purpose: .unlock) { success in
                if success {
                    GestureLockManager.shared.unlock()
                } else {
                    // 如果忘记密码（内部如果设计了忘记密码的逻辑，或者一直输错）
                    // VerifyView 内部只会提示错误，忘记密码需要加个入口
                }
            }
        }
        .environment(\.gestureLockStore, dependencies.gestureLockStore)
    }
}
