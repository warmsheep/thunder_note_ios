import Foundation

/// 与后端 `Message` 实体字段保持一致（与 Android `Message.java` 对齐）。
/// 注意：
/// - 后端 `id` 在已确认消息中非空；本地 pending 消息 id 为 0 / nil。
/// - `clientRequestId` 是发送方生成的 UUID，用于幂等与本地匹配。
/// - `createdAt` 走字符串持久化，UI 层按需解析。
public struct Message: Codable, Sendable, Equatable, Identifiable {
    public var id: Int64?
    public var senderId: Int64?
    public var receiverId: Int64?
    public var content: String?
    public var readStatus: Bool?
    public var flashNoteId: Int64?
    public var clientRequestId: String?
    public var role: String?
    public var createdAt: String?
    public var mediaType: String?
    public var mediaUrl: String?
    public var mediaDuration: Int?
    public var thumbnailUrl: String?
    public var fileName: String?
    public var fileSize: Int64?
    public var payload: CardPayload?

    public init(
        id: Int64? = nil,
        senderId: Int64? = nil,
        receiverId: Int64? = nil,
        content: String? = nil,
        readStatus: Bool? = nil,
        flashNoteId: Int64? = nil,
        clientRequestId: String? = nil,
        role: String? = nil,
        createdAt: String? = nil,
        mediaType: String? = nil,
        mediaUrl: String? = nil,
        mediaDuration: Int? = nil,
        thumbnailUrl: String? = nil,
        fileName: String? = nil,
        fileSize: Int64? = nil,
        payload: CardPayload? = nil
    ) {
        self.id = id
        self.senderId = senderId
        self.receiverId = receiverId
        self.content = content
        self.readStatus = readStatus
        self.flashNoteId = flashNoteId
        self.clientRequestId = clientRequestId
        self.role = role
        self.createdAt = createdAt
        self.mediaType = mediaType
        self.mediaUrl = mediaUrl
        self.mediaDuration = mediaDuration
        self.thumbnailUrl = thumbnailUrl
        self.fileName = fileName
        self.fileSize = fileSize
        self.payload = payload
    }

    public var resolvedMediaType: MessageMediaType {
        MessageMediaType.resolve(mediaType)
    }
}

/// `POST /api/messages/list` 请求体。`flashNoteId` 与 `peerUserId`
/// 至多其一非空（同时存在时按 `flashNoteId` 过滤）。
public struct MessageListRequest: Encodable, Sendable {
    public let flashNoteId: Int64?
    public let peerUserId: Int64?
    public let page: Int?
    public let limit: Int?

    public init(flashNoteId: Int64?, peerUserId: Int64?, page: Int?, limit: Int?) {
        self.flashNoteId = flashNoteId
        self.peerUserId = peerUserId
        self.page = page
        self.limit = limit
    }
}

/// `POST /api/messages/delete-batch` 请求体。
public struct MessageBatchDeleteRequest: Encodable, Sendable {
    public let ids: [Int64]

    public init(ids: [Int64]) {
        self.ids = ids
    }
}
