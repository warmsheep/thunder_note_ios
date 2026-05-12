import SwiftUI

@main
struct ThunderNoteApp: App {
    @StateObject private var dependencies = AppDependencies()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // App 进程启动时最早期就注册后台任务（必须在 main 返回前完成）
        SyncTaskManager.shared.register()
        // D2-I6-14 注册崩溃捕获
        CrashHandler.install()
        // D2-I6-13 初始化 DebugLog（触发轮换）
        _ = DebugLog.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(dependencies)
                .environmentObject(dependencies.session)
                .environmentObject(dependencies.authViewModel)
                .environmentObject(dependencies.serverConfigObservable)
                .environmentObject(dependencies.favoriteRegistry)
                .environmentObject(dependencies.syncCoordinator)
                .task {
                    // D2-I7-06/07 注入 Coordinator
                    SyncTaskManager.shared.setCoordinator(dependencies.syncCoordinator)
                    dependencies.bootstrap()
                }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                // 退到后台时调度下一次刷新 / 重试
                SyncTaskManager.shared.scheduleBackgroundTasks()
                // D2-I6-17 手势锁计时
                GestureLockManager.shared.onBackground()
            } else if newPhase == .active {
                // D2-I6-17 手势锁验证
                let username: String? = {
                    if case .authenticated(let u) = dependencies.session.state { return u.username }
                    return nil
                }()
                GestureLockManager.shared.onForeground(username: username, store: dependencies.gestureLockStore)
                
                // 回到前台主动 pull 一次（D2-I7-02 验收要求）
                // 只有登录态下有效，SyncCoordinator 会处理
                Task {
                    await dependencies.syncCoordinator.backgroundPull()
                }
            }
        }
    }
}
