import Combine
import Foundation

public protocol MessageRepository: Sendable {
    /// 拉取一页消息。`page` 1-based（与 Android / 后端一致）。
    /// 后端返回时排序方式默认 desc（最新在前）；调用方负责按需重排。
    func listMessages(
        key: ConversationKey,
        page: Int,
        limit: Int
    ) async throws -> PageData<Message>

    /// 发送消息（基础消息或卡片消息均通过 `POST /api/messages`）。
    /// `message.clientRequestId` 由调用方生成 UUID。
    func send(_ message: Message) async throws -> Message

    /// 删除一条消息（仅自己发送或收到的消息）。
    func delete(id: Int64) async throws

    /// 批量删除（最多 50 条）。
    func deleteBatch(ids: [Int64]) async throws

    /// 清空收集箱（`flashNoteId=-1`）下当前用户所有消息。
    func clearInbox() async throws

    /// 把已有消息合并成 COMPOSITE 卡片消息（D2-I3-17）。`POST /api/messages/merge`。
    func merge(_ request: MessageMergeRequest) async throws -> Message

    /// 直接基于客户端预上传媒体新建 COMPOSITE 卡片消息（D2-I3-19）。
    /// `POST /api/messages/composite`。
    func createComposite(_ request: CompositeMessageRequest) async throws -> Message

    /// D2-I6-08 当前用户参与的全部消息总数（sender 或 receiver 为 self），与
    /// 服务端 `GET /api/messages/count` 对齐；与 Android `MessageRepository.countMessages` 等价。
    func countMessages() async throws -> Int64

    /// D2-I7-04 Step 2D-2 读本会话本地缓存的消息；UI 首屏 / 离线下能拿到上次同步
    /// 落库的 `messages_local` 快照。默认返回空数组（未接本地 DAO 的实现）。
    func listLocalMessages(key: ConversationKey, limit: Int) -> [Message]

    /// D2-I7-04 Step 2D-2 向 `messages_local` upsert 一条服务端确认过的消息（正常
    /// 只在客户端发送 / merge / composite 成功后调），让本地表与 UI 一致。
    func upsertLocalMessage(_ message: Message)

    /// D2-I7-04 Step 2D-2 从本地表删除一条或一批消息（服务端 delete 成功后顺手清本地）。
    func removeLocalMessages(ids: [Int64])

    /// D2-I7-04 Step 2D-2 清空一个会话在本地表的全部消息（用于 clearInbox / 退出多会话场景）。
    func clearLocalConversation(key: ConversationKey)

    /// D2-I7-04 Step 2D-2 订阅一个会话的本地变动事件。`SyncCoordinator` 在 pull 落库后
    /// 会推一轮 `Void`；`ChatViewModel` 收到后重读 `listLocalMessages` 并 merge。
    /// 默认返回 Empty publisher（不发任何事件）。
    func conversationChanged(for key: ConversationKey) -> AnyPublisher<Void, Never>
}

public extension MessageRepository {
    func listLocalMessages(key: ConversationKey, limit: Int) -> [Message] { [] }
    func upsertLocalMessage(_ message: Message) {}
    func removeLocalMessages(ids: [Int64]) {}
    func clearLocalConversation(key: ConversationKey) {}
    func conversationChanged(for key: ConversationKey) -> AnyPublisher<Void, Never> {
        Empty<Void, Never>().eraseToAnyPublisher()
    }
}

public final class MessageRepositoryImpl: MessageRepository, @unchecked Sendable {
    private let apiClient: APIClient
    private let messageLocalDao: MessageLocalDao?
    private let usernameProvider: @Sendable () -> String?
    private let currentUserIdProvider: @Sendable () -> Int64?
    private let conversationsChangedSubject = PassthroughSubject<Set<Int64>, Never>()
    private var conversationsChangedCancellable: AnyCancellable?

    public init(
        apiClient: APIClient,
        messageLocalDao: MessageLocalDao? = nil,
        usernameProvider: @Sendable @escaping () -> String? = { nil },
        currentUserIdProvider: @Sendable @escaping () -> Int64? = { nil }
    ) {
        self.apiClient = apiClient
        self.messageLocalDao = messageLocalDao
        self.usernameProvider = usernameProvider
        self.currentUserIdProvider = currentUserIdProvider
    }

    /// `AppDependencies` 在 `SyncCoordinator` 创建后调一次，把 `conversationsChangedPublisher`
    /// 转发到本 repository。这样不需要让 repository 反向持有 SyncCoordinator，避免循环引用。
    public func bindConversationsChanged(_ publisher: AnyPublisher<Set<Int64>, Never>) {
        conversationsChangedCancellable = publisher.sink { [weak self] keys in
            self?.conversationsChangedSubject.send(keys)
        }
    }

    public func listMessages(
        key: ConversationKey,
        page: Int,
        limit: Int
    ) async throws -> PageData<Message> {
        let request = MessageListRequest(
            flashNoteId: key.flashNoteIdForRequest,
            peerUserId: key.peerUserIdForRequest,
            page: page,
            limit: limit
        )
        let body = try JSONEncoder.tnDefault.encode(request)
        let endpoint = Endpoint<PageData<Message>>(
            method: .post,
            path: "/api/messages/list",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        return try await apiClient.send(endpoint)
    }

    public func send(_ message: Message) async throws -> Message {
        let body = try JSONEncoder.tnDefault.encode(message)
        let endpoint = Endpoint<Message>(
            method: .post,
            path: "/api/messages",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        return try await apiClient.send(endpoint)
    }

    public func delete(id: Int64) async throws {
        let endpoint = Endpoint<EmptyResponse>(
            method: .delete,
            path: "/api/messages/\(id)",
            body: nil,
            requiresAuth: true
        )
        _ = try await apiClient.send(endpoint)
    }

    public func deleteBatch(ids: [Int64]) async throws {
        guard !ids.isEmpty else { return }
        let body = try JSONEncoder.tnDefault.encode(MessageBatchDeleteRequest(ids: ids))
        let endpoint = Endpoint<EmptyResponse>(
            method: .post,
            path: "/api/messages/delete-batch",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        _ = try await apiClient.send(endpoint)
    }

    public func clearInbox() async throws {
        let endpoint = Endpoint<EmptyResponse>(
            method: .delete,
            path: "/api/messages/clear-inbox",
            body: nil,
            requiresAuth: true
        )
        _ = try await apiClient.send(endpoint)
    }

    public func merge(_ request: MessageMergeRequest) async throws -> Message {
        let body = try JSONEncoder.tnDefault.encode(request)
        let endpoint = Endpoint<Message>(
            method: .post,
            path: "/api/messages/merge",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        return try await apiClient.send(endpoint)
    }

    public func createComposite(_ request: CompositeMessageRequest) async throws -> Message {
        let body = try JSONEncoder.tnDefault.encode(request)
        let endpoint = Endpoint<Message>(
            method: .post,
            path: "/api/messages/composite",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        return try await apiClient.send(endpoint)
    }

    // MARK: - D2-I7-04 Step 2D-2 本地表接口

    public func listLocalMessages(key: ConversationKey, limit: Int) -> [Message] {
        guard let dao = messageLocalDao,
              let username = usernameProvider(), !username.isEmpty else {
            return []
        }
        return (try? dao.listByConversation(
            username: username,
            conversationKey: key.persistenceKey,
            limit: limit
        )) ?? []
    }

    public func upsertLocalMessage(_ message: Message) {
        guard let dao = messageLocalDao,
              let username = usernameProvider(), !username.isEmpty,
              let key = ConversationKeyResolver.resolveForMessage(
                  message, currentUserId: currentUserIdProvider()
              ) else {
            return
        }
        try? dao.upsert(message, username: username, conversationKey: key)
        // D2-I7-05 Step 2B：广播变动，让 ChatViewModel 通过 conversationChanged
        // 自动 mergeLocalMessages（mergePreservingPending 会丢弃重复 sent 项）。
        conversationsChangedSubject.send([key])
    }

    public func removeLocalMessages(ids: [Int64]) {
        guard let dao = messageLocalDao,
              let username = usernameProvider(), !username.isEmpty,
              !ids.isEmpty else { return }
        try? dao.deleteByIds(username: username, ids: ids)
    }

    public func clearLocalConversation(key: ConversationKey) {
        guard let dao = messageLocalDao,
              let username = usernameProvider(), !username.isEmpty else { return }
        try? dao.deleteByConversation(username: username, conversationKey: key.persistenceKey)
    }

    public func conversationChanged(for key: ConversationKey) -> AnyPublisher<Void, Never> {
        let targetKey = key.persistenceKey
        return conversationsChangedSubject
            .filter { $0.contains(targetKey) }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    public func countMessages() async throws -> Int64 {
        let endpoint = Endpoint<MessageCountResponse>(
            method: .get,
            path: "/api/messages/count",
            requiresAuth: true
        )
        return try await apiClient.send(endpoint).value
    }
}

/// `GET /api/messages/count` 返回 `data=Long`，透明包装一层避免 ApiResponse 解码时
/// 把整数解码到 Int64 出问题。
public struct MessageCountResponse: Decodable, Sendable {
    public let value: Int64

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(Int64.self)
    }
}
