import Combine
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

    /// 队列状态发生变化（增删改）时，除了更新 `pendingCount`，还通过此 publisher 广播，
    /// 方便聊天页刷新自己会话下的待发送消息。
    public var pendingQueueChangedPublisher: AnyPublisher<Void, Never> {
        pendingQueueChangedSubject.eraseToAnyPublisher()
    }
    private let pendingQueueChangedSubject = PassthroughSubject<Void, Never>()

    /// D2-I7-04 每次 pull 将本轮接收到的消息写完 `messages_local` 后，用本 subject 广播
    /// 变动的 `conversation_key` 集合。化身为 `eraseToAnyPublisher()` 给 `MessageRepository`
    /// / `ChatViewModel` 订阅，与 Android `MessageRepository.refreshLocalConversations(keys)` 等价。
    public var conversationsChangedPublisher: AnyPublisher<Set<Int64>, Never> {
        conversationsChangedSubject.eraseToAnyPublisher()
    }
    private let conversationsChangedSubject = PassthroughSubject<Set<Int64>, Never>()

    private let syncRepository: SyncRepository
    private let onPullSucceeded: @Sendable (SyncPullResponse) async -> Void
    private let pendingMessageDao: PendingMessageDao?
    private let messageLocalDao: MessageLocalDao?
    private let syncEngine: SyncEngine?
    private let usernameProvider: @Sendable () -> String?
    private let currentUserIdProvider: @Sendable () -> Int64?
    /// 防抖：bootstrap 多次触发只跑一次。
    private var bootstrapTask: Task<Void, Never>? = nil

    public init(
        syncRepository: SyncRepository,
        pendingMessageDao: PendingMessageDao? = nil,
        messageLocalDao: MessageLocalDao? = nil,
        syncEngine: SyncEngine? = nil,
        usernameProvider: @Sendable @escaping () -> String? = { nil },
        currentUserIdProvider: @Sendable @escaping () -> Int64? = { nil },
        onPullSucceeded: @escaping @Sendable (SyncPullResponse) async -> Void = { _ in }
    ) {
        self.syncRepository = syncRepository
        self.pendingMessageDao = pendingMessageDao
        self.messageLocalDao = messageLocalDao
        self.syncEngine = syncEngine
        self.usernameProvider = usernameProvider
        self.currentUserIdProvider = currentUserIdProvider
        self.onPullSucceeded = onPullSucceeded
    }

    /// 让 SyncEngine 在队列变动后调本方法刷新 `pendingCount`。
    /// SyncEngine 与 Coordinator 互为弱引用，该方法可从任意线程上调。
    nonisolated public func refreshPendingCount() {
        Task { @MainActor [weak self] in
            self?.reloadPendingCount()
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

    /// D2-I7-07 后台静默刷新：仅执行 pull
    public func backgroundPull() async {
        // 后台刷新允许重入（系统调度的我们尽量接），但如果 state==syncing 也可以忽略
        guard state != .syncing else { return }
        state = .syncing
        do {
            let response = try await syncRepository.pull()
            lastServerTime = response.serverTime ?? lastServerTime
            persistPulledMessages(response)
            state = .idle
            await onPullSucceeded(response)
        } catch let api as APIError {
            state = .failure(api.displayMessage)
        } catch {
            state = .failure(error.localizedDescription)
        }
        reloadPendingCount()
    }
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
            persistPulledMessages(response)
            state = .idle
            await onPullSucceeded(response)
        } catch let api as APIError {
            state = .failure(api.displayMessage)
            transientMessage = api.displayMessage
        } catch {
            state = .failure(error.localizedDescription)
            transientMessage = error.localizedDescription
        }
        reloadPendingCount()
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
            reloadPendingCount()
            // drain 异步执行，不让 UI 等待网络。
            Task { [weak self] in
                _ = await engine.drain()
                self?.reloadPendingCount()
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
            reloadPendingCount()
            Task { [weak self] in
                _ = await engine.drain()
                await MainActor.run { self?.reloadPendingCount() }
            }
            return id
        } catch {
            transientMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            return nil
        }
    }

    /// 读取指定会话下的待发送消息，供 ChatViewModel 用来合并乐观 UI 显示（D2-I7-05 Step 2C）。
    public func listPendingMessages(for key: ConversationKey) -> [PendingMessageLocal] {
        guard let dao = pendingMessageDao, let username = usernameProvider(), !username.isEmpty else {
            return []
        }
        return (try? dao.listByConversation(username: username, conversationKey: key.persistenceKey)) ?? []
    }

    /// 闪记 / 私聊会话的本地 conversationKey：直接走 `ConversationKeyResolver`
    /// 与 Android `ConversationKeyUtil.resolve` 完全一致。
    private static func conversationKey(flashNoteId: Int64?, peerUserId: Int64?) -> Int64 {
        ConversationKeyResolver.resolve(flashNoteId: flashNoteId, peerUserId: peerUserId) ?? 0
    }

    /// 用户点击待同步列表里的「重试」。
    public func retryPending(localId: Int64) async {
        guard let syncEngine else { return }
        await syncEngine.retry(localId: localId)
        reloadPendingCount()
    }

    /// 后台恢复 / 全局重试
    public func retryAllPending() async {
        guard let syncEngine else { return }
        await syncEngine.retryAll()
        reloadPendingCount()
    }

    /// 用户点击待同步列表里的「删除」。
    public func deletePending(localId: Int64) async {
        guard let syncEngine else { return }
        await syncEngine.remove(localId: localId)
        reloadPendingCount()
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
            try? messageLocalDao?.deleteAllForUsername(username)
        }
    }

    /// D2-I7-04 把 pull / bootstrap 收到的 messages 写入本地 `messages_local`，并广播
    /// 变动的 `conversation_key` 集合给订阅方（`MessageRepository.refreshLocalConversations`）。
    /// 失败安静忽略：DAO 写错只影响本地缓存，不应阻断同步链。
    private func persistPulledMessages(_ response: SyncPullResponse) {
        guard let dao = messageLocalDao,
              let username = usernameProvider(), !username.isEmpty,
              !response.messages.isEmpty else {
            return
        }
        let currentUserId = currentUserIdProvider()
        var pairs: [(Message, Int64)] = []
        var changedKeys: Set<Int64> = []
        for message in response.messages {
            guard message.id != nil else { continue }
            guard let key = ConversationKeyResolver.resolveForMessage(message, currentUserId: currentUserId) else {
                continue
            }
            pairs.append((message, key))
            changedKeys.insert(key)
        }
        guard !pairs.isEmpty else { return }
        do {
            try dao.upsertAll(pairs, username: username)
            conversationsChangedSubject.send(changedKeys)
        } catch {
            // 写入失败不阻塞同步链；记录到 transient 只在 debug 时有用，正常用户感知很弱。
            transientMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    /// 从 DAO 拉最新 pendingCount。
    public func reloadPendingCount() {
        guard let dao = pendingMessageDao, let username = usernameProvider() else { return }
        do {
            let count = try dao.countDispatchable(username: username)
            pendingCount = count
            pendingQueueChangedSubject.send()
        } catch {
            // ignore
        }
    }

    private func runBootstrap() async {
        state = .syncing
        do {
            let response = try await syncRepository.bootstrap()
            lastServerTime = response.serverTime ?? lastServerTime
            persistPulledMessages(response)
            state = .idle
            await onPullSucceeded(response)
        } catch let api as APIError {
            state = .failure(api.displayMessage)
            transientMessage = api.displayMessage
        } catch {
            state = .failure(error.localizedDescription)
            transientMessage = error.localizedDescription
        }
        reloadPendingCount()
    }
}
