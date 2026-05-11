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

    /// D2-I7-05 Step 2B：把一条文本消息入队 + 触发 drain。
    /// - 用于 ChatViewModel 在网络失败 / 用户离线场景把消息推入 PendingMessage 队列；
    ///   `clientRequestId` 由调用方生成（与 Android 一致：UUID 全局唯一，幂等去重）。
    /// - 入队成功返回 localId；如果 username 缺失返回 nil。
    /// - drain 会在 Task 中异步发起，不阻塞调用方。
    @discardableResult
    public func enqueueText(
        flashNoteId: Int64?,
        peerUserId: Int64?,
        content: String,
        clientRequestId: String
    ) async -> Int64? {
        guard let dao = pendingMessageDao,
              let engine = syncEngine,
              let username = usernameProvider(), !username.isEmpty else {
            return nil
        }
        let pending = PendingMessageLocal(
            username: username,
            conversationKey: Self.conversationKey(flashNoteId: flashNoteId, peerUserId: peerUserId),
            flashNoteId: flashNoteId,
            peerUserId: peerUserId,
            clientRequestId: clientRequestId,
            mediaType: MessageMediaType.text.rawValue,
            content: content,
            status: .queued
        )
        do {
            let id = try await engine.enqueue(pending)
            await reloadPendingCount()
            // drain 异步执行，不让 UI 等待网络。
            Task { [weak self] in
                _ = await engine.drain()
                await self?.reloadPendingCount()
            }
            return id
        } catch {
            // DAO 写入失败极少见（sqlite 满 / IO 错误）；记录到 transient 让 UI 提示。
            transientMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            _ = dao
            return nil
        }
    }

    /// 把已有 PendingMessage（例如 ChatViewModel 上层构造好的媒体消息）入队 + drain。
    @discardableResult
    public func enqueue(_ pending: PendingMessageLocal) async -> Int64? {
        guard let engine = syncEngine else { return nil }
        do {
            let id = try await engine.enqueue(pending)
            await reloadPendingCount()
            Task { [weak self] in
                _ = await engine.drain()
                await self?.reloadPendingCount()
            }
            return id
        } catch {
            transientMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            return nil
        }
    }

    /// 闪记 / 私聊会话的本地 conversationKey：与 Android `conversation_key` 计算等价：
    /// `flashNoteId` 优先（正数），否则 `-peerUserId`（负数避免冲突）。
    private static func conversationKey(flashNoteId: Int64?, peerUserId: Int64?) -> Int64 {
        if let flashNoteId, flashNoteId != 0 { return flashNoteId }
        if let peerUserId, peerUserId != 0 { return -peerUserId }
        return 0
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
