import Foundation

/// D2-I7-05 同步引擎。
///
/// 设计要点（与 Android `PendingMessageDispatcher` 对齐）：
/// - 单 actor 串行消费 PendingMessage 队列；外部并发调用 `drain()` 也只会有一个真正在跑。
/// - 取下一个待派发条目走 `PendingMessageDao.pickNextDispatchable`（QUEUED 优先 → FAILED 兜底）。
/// - 派发委托 `PendingMessageSender.send`：iOS 端 Step 2A 暂不绑定 MessageRepository，
///   该实现由 Step 2B 接入 `POST /api/messages` / 媒体上传链路。
/// - 失败：`attemptCount += 1`，标 `FAILED` 并写 `errorMessage`。
///   `attemptCount >= maxAttempts` 后仍保留 `FAILED`，等用户手动重试或登录后恢复 worker 重置状态。
/// - 成功：从 `pending_messages` 表删除该行（与 Android `STATUS_SENT` 后由消费方落库 + 删 pending 对齐）。
public protocol PendingMessageSender: Sendable {
    /// 派发单条 pending message。
    /// - returns: 服务端返回的消息 id（用于诊断 / 回写 server_message_id）；可为 nil。
    /// - throws: 失败抛错；`SyncEngine` 据此标记重试。
    func send(_ pending: PendingMessageLocal) async throws -> Int64?
}

public actor SyncEngine {
    public enum DispatchResult: Equatable, Sendable {
        case idle           // 队列空
        case dispatched(Int) // 本次成功派发数
    }

    private let dao: PendingMessageDao
    private let sender: PendingMessageSender
    private let usernameProvider: @Sendable () -> String?
    /// 超过 `maxAttempts` 之后仍标 `FAILED`，但 `drain()` 不会自动再选中（因为
    /// `pickNextDispatchable` 取所有 FAILED 都会选；这里在 actor 内额外按 attemptCount 跳过）。
    public let maxAttempts: Int
    /// 上层（SyncCoordinator）订阅 `onQueueChanged` 拉最新 pendingCount。
    private var listener: (@Sendable () -> Void)?
    private var draining: Bool = false

    public init(
        dao: PendingMessageDao,
        sender: PendingMessageSender,
        usernameProvider: @Sendable @escaping () -> String?,
        maxAttempts: Int = 5
    ) {
        self.dao = dao
        self.sender = sender
        self.usernameProvider = usernameProvider
        self.maxAttempts = maxAttempts
    }

    /// 注册队列变化监听；每次 insert / update / delete 之后会调一次（不传内容，
    /// 调用方按需通过 dao 查最新 count / list）。
    public func setOnQueueChanged(_ listener: (@Sendable () -> Void)?) {
        self.listener = listener
    }

    /// 入队 + 触发派发。返回新插入的 localId。
    @discardableResult
    public func enqueue(_ message: PendingMessageLocal) throws -> Int64 {
        let id = try dao.insert(message)
        listener?()
        return id
    }

    /// 用户手动重试 / 应用进入前台时触发 drain。
    /// 多次并发调用只会有一个真正跑（actor 已串行；通过 `draining` 抢占避免重入嵌套）。
    @discardableResult
    public func drain() async -> DispatchResult {
        guard let username = usernameProvider(), !username.isEmpty else { return .idle }
        guard !draining else { return .idle }
        draining = true
        defer { draining = false }

        var dispatched = 0
        while true {
            // `try? T?` 得到 `T??`，需要 `?? nil` 平铺再 guard let。
            let next = (try? dao.pickNextDispatchable(username: username)) ?? nil
            guard let pending = next else { break }
            // 超过 maxAttempts 的 FAILED 项不再自动重试，但仍保留行 / 出现在待同步列表里。
            if pending.status == .failed && pending.attemptCount >= maxAttempts {
                break
            }
            await dispatchOne(pending)
            dispatched += 1
            listener?()
        }
        listener?()
        return dispatched == 0 ? .idle : .dispatched(dispatched)
    }

    /// 用户在待同步列表里点「重试」时调：把 attemptCount 重置为 0，状态置回 QUEUED，再 drain。
    public func retry(localId: Int64) async {
        let found = (try? dao.findByLocalId(localId)) ?? nil
        guard var pending = found else { return }
        pending.status = .queued
        pending.errorMessage = nil
        pending.attemptCount = 0
        try? dao.update(pending)
        listener?()
        _ = await drain()
    }

    /// 用户在待同步列表里点「删除」。
    public func remove(localId: Int64) {
        try? dao.delete(localId: localId)
        listener?()
    }

    /// 登出全清。
    public func clear(username: String) {
        try? dao.clear(username: username)
        listener?()
    }

    // MARK: - private

    private func dispatchOne(_ pending: PendingMessageLocal) async {
        var current = pending
        current.status = .sending
        current.errorMessage = nil
        try? dao.update(current)

        do {
            let serverMessageId = try await sender.send(current)
            // 成功：删除 pending 行（与 Android `STATUS_SENT` 后由 helper 落库 + delete pending 对齐）。
            _ = serverMessageId
            try? dao.delete(localId: current.localId)
        } catch {
            current.status = .failed
            current.attemptCount += 1
            current.errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            try? dao.update(current)
        }
    }
}

/// `PendingMessageDao` 是 actor-isolated 访问的，但其实现内部是同步 + 线程安全的（走串行队列）。
/// 这里加一个空 extension 表明用法预期：DAO 是 Sendable，actor 内安全直接调。
extension SQLitePendingMessageDao: @unchecked Sendable {}
