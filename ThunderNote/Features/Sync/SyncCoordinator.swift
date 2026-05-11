import Foundation
import SwiftUI

/// D2-I7-08 手动同步入口的协调对象。
///
/// - `state`（idle / syncing / failure）驱动同步按钮 UI
/// - `pendingCount` 来自 `PendingMessageDao.countDispatchable(username:)`（D2-I7-05 / Step 2A）；
///   `SyncEngine` 在队列变动后回调 `refreshPendingCount()`。
/// - `bootstrapIfNeeded()` 登录后单飞调一次；`manualSync()` 串行执行
///   `SyncEngine.drain() → syncRepository.push(empty) → syncRepository.pull()`。
/// - 失败走 transientMessage，由 UI 接 `ToastCenter`。
@MainActor
public final class SyncCoordinator: ObservableObject {
    public enum State: Equatable {
        case idle
        case syncing
        case failure(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var pendingCount: Int = 0
    @Published public var transientMessage: String? = nil
    @Published public private(set) var lastServerTime: String? = nil

    private let syncRepository: SyncRepository
    private let onPullSucceeded: @Sendable (SyncPullResponse) async -> Void
    private let pendingMessageDao: PendingMessageDao?
    private let syncEngine: SyncEngine?
    private let usernameProvider: @Sendable () -> String?
    /// 防抖：bootstrap 多次触发只跑一次。
    private var bootstrapTask: Task<Void, Never>? = nil

    public init(
        syncRepository: SyncRepository,
        pendingMessageDao: PendingMessageDao? = nil,
        syncEngine: SyncEngine? = nil,
        usernameProvider: @Sendable @escaping () -> String? = { nil },
        onPullSucceeded: @escaping @Sendable (SyncPullResponse) async -> Void = { _ in }
    ) {
        self.syncRepository = syncRepository
        self.pendingMessageDao = pendingMessageDao
        self.syncEngine = syncEngine
        self.usernameProvider = usernameProvider
        self.onPullSucceeded = onPullSucceeded
    }

    /// 让 SyncEngine 在队列变动后调本方法刷新 `pendingCount`。
    /// SyncEngine 与 Coordinator 互为弱引用，该方法可从任意线程上调。
    nonisolated public func refreshPendingCount() {
        Task { [weak self] in
            await self?.reloadPendingCount()
        }
    }

    /// 登录后调一次：单飞控制，重复调用复用现有 Task。
    public func bootstrapIfNeeded() {
        if let bootstrapTask, !bootstrapTask.isCancelled {
            return
        }
        bootstrapTask = Task { [weak self] in
            await self?.runBootstrap()
        }
    }

    /// D2-I7-08 手动同步：
    /// 1. SyncEngine.drain() 消费本地 PendingMessage 队列（Step 2B 接入真实 sender 后会真正发送）
    /// 2. push 空 payload（与 Android `syncAll` 链路一致，payload 由 Step 2B 的 sender 填充）
    /// 3. pull 增量数据。
    public func manualSync() async {
        guard state != .syncing else { return }
        state = .syncing
        do {
            if let syncEngine {
                _ = await syncEngine.drain()
            }
            _ = try await syncRepository.push(SyncPushRequest())
            let response = try await syncRepository.pull()
            lastServerTime = response.serverTime ?? lastServerTime
            state = .idle
            await onPullSucceeded(response)
        } catch let api as APIError {
            state = .failure(api.displayMessage)
            transientMessage = api.displayMessage
        } catch {
            state = .failure(error.localizedDescription)
            transientMessage = error.localizedDescription
        }
        await reloadPendingCount()
    }

    /// 用户点击待同步列表里的「重试」。
    public func retryPending(localId: Int64) async {
        guard let syncEngine else { return }
        await syncEngine.retry(localId: localId)
        await reloadPendingCount()
    }

    /// 用户点击待同步列表里的「删除」。
    public func deletePending(localId: Int64) async {
        guard let syncEngine else { return }
        await syncEngine.remove(localId: localId)
        await reloadPendingCount()
    }

    public func clearTransientMessage() {
        transientMessage = nil
    }

    /// 登出时调，让下一次登录重新触发 bootstrap；清本账号未发送 PendingMessage。
    public func resetForSignOut() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        state = .idle
        pendingCount = 0
        lastServerTime = nil
        transientMessage = nil
        if let username = usernameProvider(), !username.isEmpty {
            try? pendingMessageDao?.clear(username: username)
        }
    }

    /// 从 DAO 拉最新 pendingCount。
    private func reloadPendingCount() async {
        guard let dao = pendingMessageDao,
              let username = usernameProvider(), !username.isEmpty else {
            pendingCount = 0
            return
        }
        let next = (try? dao.countDispatchable(username: username)) ?? 0
        if pendingCount != next { pendingCount = next }
    }

    private func runBootstrap() async {
        state = .syncing
        do {
            let response = try await syncRepository.bootstrap()
            lastServerTime = response.serverTime ?? lastServerTime
            state = .idle
            await onPullSucceeded(response)
        } catch let api as APIError {
            state = .failure(api.displayMessage)
            transientMessage = api.displayMessage
        } catch {
            state = .failure(error.localizedDescription)
            transientMessage = error.localizedDescription
        }
        await reloadPendingCount()
    }
}
