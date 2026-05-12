import BackgroundTasks
import UIKit

/// D2-I7-06 & D2-I7-07 后台任务管理
///
/// `tn.sync.recovery`: `BGProcessingTask` 用于重试失败的 pending 消息 + pull。
/// `tn.sync.refresh`: `BGAppRefreshTask` 用于后台静默拉取新消息。
@MainActor
public final class SyncTaskManager: Sendable {
    public static let shared = SyncTaskManager()

    public let recoveryTaskIdentifier = "tn.sync.recovery"
    public let refreshTaskIdentifier = "tn.sync.refresh"

    private var syncCoordinator: SyncCoordinator?

    private init() {}

    /// 在 App.init() 中调用（必须在 main 返回前完成）
    public func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: recoveryTaskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            self.handleRecovery(task: processingTask)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleRefresh(task: refreshTask)
        }
    }

    /// 在启动完毕后注入 coordinator
    public func setCoordinator(_ coordinator: SyncCoordinator) {
        self.syncCoordinator = coordinator
    }

    /// App 进入后台时调度
    public func scheduleBackgroundTasks() {
        scheduleRecoveryIfNeeded()
        scheduleRefresh()
    }

    /// 登出时取消所有调度
    public func cancelAll() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
    }

    // MARK: - Recovery (BGProcessingTask)

    private func scheduleRecoveryIfNeeded() {
        // 只有有 pending 时才需要调度 recovery
        guard let coordinator = syncCoordinator, coordinator.pendingCount > 0 else { return }
        
        let request = BGProcessingTaskRequest(identifier: recoveryTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        // 尽快执行
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Scheduled recovery task")
        } catch {
            print("Could not schedule recovery task: \(error)")
        }
    }

    private func handleRecovery(task: BGProcessingTask) {
        // 如果系统要求提前结束，则标记取消
        let operationTask = Task {
            await syncCoordinator?.retryAllPending()
            await syncCoordinator?.manualSync()
        }

        task.expirationHandler = {
            operationTask.cancel()
        }

        Task {
            _ = await operationTask.result
            task.setTaskCompleted(success: !operationTask.isCancelled)
            
            // 如果还有 pending，再次调度
            await MainActor.run {
                if let coordinator = self.syncCoordinator, coordinator.pendingCount > 0 {
                    self.scheduleRecoveryIfNeeded()
                }
            }
        }
    }

    // MARK: - Refresh (BGAppRefreshTask)

    private func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        // 每 15 分钟尝试唤醒一次（实际由系统调度策略决定）
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Scheduled refresh task")
        } catch {
            print("Could not schedule refresh task: \(error)")
        }
    }

    private func handleRefresh(task: BGAppRefreshTask) {
        // 确保下次还能被调度
        scheduleRefresh()

        let operationTask = Task {
            // 后台静默刷新，只 pull，不 push
            await syncCoordinator?.backgroundPull()
        }

        task.expirationHandler = {
            operationTask.cancel()
        }

        Task {
            _ = await operationTask.result
            task.setTaskCompleted(success: !operationTask.isCancelled)
        }
    }
}
