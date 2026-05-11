import Foundation

/// D2-I7 同步主链。
///
/// 当前 Step 1 范围（与 Android `SyncRepositoryImpl` 对齐）：
/// - `bootstrap()` 调 `POST /api/sync/bootstrap`，落 `sync_meta`（last_message_created_at / server_time）
/// - `pull()` 调 `POST /api/sync/pull`，按 `sync_meta.last_message_created_at` 走增量
/// - `push(_:)` 调 `POST /api/sync/push`，由调用方组装 payload
///
/// Step 2（未来）：把 pull 落库到 flash_notes / collections / favorites / messages 本地表，
/// 触发 `MessageRepository.refreshLocalConversations`（经验 75）；PendingMessage 队列由 SyncEngine
/// 单 actor 串行回放。
public protocol SyncRepository: Sendable {
    /// 登录后或冷启动后调一次。等价 `pull(lastMessageCreatedAt:nil)` + `bootstrap=true` 标记。
    func bootstrap() async throws -> SyncPullResponse

    /// 增量 / 全量 pull。`lastMessageCreatedAt` 为 nil 时全量。
    /// 成功后会更新 `sync_meta.last_message_created_at` 与 `server_time`。
    func pull() async throws -> SyncPullResponse

    /// push 本地写入到服务端。当前 Step 1 不组装 payload，给调用方传入。
    func push(_ payload: SyncPushRequest) async throws -> SyncPushResponse
}

public final class SyncRepositoryImpl: SyncRepository, @unchecked Sendable {
    private let apiClient: APIClient
    private let syncMetaDao: SyncMetaDao
    private let usernameProvider: @Sendable () -> String?

    public init(
        apiClient: APIClient,
        syncMetaDao: SyncMetaDao,
        usernameProvider: @Sendable @escaping () -> String?
    ) {
        self.apiClient = apiClient
        self.syncMetaDao = syncMetaDao
        self.usernameProvider = usernameProvider
    }

    public func bootstrap() async throws -> SyncPullResponse {
        let endpoint = Endpoint<SyncPullResponse>(
            method: .post,
            path: "/api/sync/bootstrap",
            body: nil,
            requiresAuth: true
        )
        let response = try await apiClient.send(endpoint)
        persistMeta(from: response)
        return response
    }

    public func pull() async throws -> SyncPullResponse {
        let lastAt = currentLastMessageCreatedAt()
        let body = try JSONEncoder.tnDefault.encode(SyncPullRequest(lastMessageCreatedAt: lastAt))
        let endpoint = Endpoint<SyncPullResponse>(
            method: .post,
            path: "/api/sync/pull",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        let response = try await apiClient.send(endpoint)
        persistMeta(from: response)
        return response
    }

    public func push(_ payload: SyncPushRequest) async throws -> SyncPushResponse {
        let body = try JSONEncoder.tnDefault.encode(payload)
        let endpoint = Endpoint<SyncPushResponse>(
            method: .post,
            path: "/api/sync/push",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        let response = try await apiClient.send(endpoint)
        if let serverTime = response.serverTime, let username = usernameProvider(), !username.isEmpty {
            try? syncMetaDao.upsert(username: username, lastMessageCreatedAt: nil, serverTime: serverTime)
        }
        return response
    }

    // MARK: - private

    private func currentLastMessageCreatedAt() -> String? {
        guard let username = usernameProvider(), !username.isEmpty else { return nil }
        return (try? syncMetaDao.loadLastMessageCreatedAt(username: username)) ?? nil
    }

    private func persistMeta(from response: SyncPullResponse) {
        guard let username = usernameProvider(), !username.isEmpty else { return }
        let nextLast = response.maxMessageCreatedAt
        try? syncMetaDao.upsert(
            username: username,
            lastMessageCreatedAt: nextLast,
            serverTime: response.serverTime
        )
    }
}
