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
}

public final class MessageRepositoryImpl: MessageRepository, @unchecked Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
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
