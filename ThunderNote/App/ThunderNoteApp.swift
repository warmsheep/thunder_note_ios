import SwiftUI

@main
struct ThunderNoteApp: App {
    @StateObject private var dependencies = AppDependencies()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // App 进程启动时最早期就注册后台任务（必须在 main 返回前完成）
        // 这里只是创建出 dependencies，依赖还在初始化阶段
        // 但注册只需要标识符和回调闭包，回调里延迟访问 coordinator 是安全的
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
                    // D2-I7-06/07 注册 TaskManager
                    SyncTaskManager.shared.register(syncCoordinator: dependencies.syncCoordinator)
                    dependencies.bootstrap()
                }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                // 退到后台时调度下一次刷新 / 重试
                SyncTaskManager.shared.scheduleBackgroundTasks()
            } else if newPhase == .active {
                // 回到前台主动 pull 一次（D2-I7-02 验收要求）
                // 只有登录态下有效，SyncCoordinator 会处理
                Task {
                    await dependencies.syncCoordinator.backgroundPull()
                }
            }
        }
    }
}
