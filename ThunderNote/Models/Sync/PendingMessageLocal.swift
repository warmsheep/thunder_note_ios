import Foundation

/// D2-I7-05 PendingMessage 本地实体。
///
/// 字段尽量与 Android `data/model/PendingMessage.java` 对齐，新增 `username` 做多账号隔离。
/// 状态机与 Android `PendingMessageDispatcher.STATUS_*` 对齐：
/// - `QUEUED`：等待发送（首次入队 / 用户重试）
/// - `PROCESSING`：派发开始（占位，避免重复消费）
/// - `UPLOADING` / `UPLOADED`：媒体消息上传中 / 已上传待发送
/// - `SENDING`：网络请求已发出
/// - `SENT`：成功（成功后立即从表删除，不会有持久化的 SENT 行）
/// - `FAILED`：本次尝试失败，`error_message` + `attempt_count` 记录现场
public struct PendingMessageLocal: Equatable, Sendable {
    public enum Status: String, Sendable {
        case queued = "QUEUED"
        case processing = "PROCESSING"
        case uploading = "UPLOADING"
        case uploaded = "UPLOADED"
        case sending = "SENDING"
        case sent = "SENT"
        case failed = "FAILED"
    }

    public var localId: Int64
    public var username: String
    public var conversationKey: Int64
    public var flashNoteId: Int64?
    public var peerUserId: Int64?
    public var clientRequestId: String?
    public var mediaType: String?
    public var content: String?
    public var localFilePath: String?
    public var remoteUrl: String?
    public var fileName: String?
    public var fileSize: Int64?
    public var mediaDuration: Int64?
    public var processedFilePath: String?
    public var thumbnailUrl: String?
    public var payloadJson: String?
    public var status: Status
    /// `createdAt` 用 epoch millis（与 Android `long createdAt` 对齐），方便排序。
    public var createdAt: Int64
    public var errorMessage: String?
    public var attemptCount: Int
    public var serverMessageId: Int64?

    public init(
        localId: Int64 = 0,
        username: String,
        conversationKey: Int64,
        flashNoteId: Int64? = nil,
        peerUserId: Int64? = nil,
        clientRequestId: String? = nil,
        mediaType: String? = nil,
        content: String? = nil,
        localFilePath: String? = nil,
        remoteUrl: String? = nil,
        fileName: String? = nil,
        fileSize: Int64? = nil,
        mediaDuration: Int64? = nil,
        processedFilePath: String? = nil,
        thumbnailUrl: String? = nil,
        payloadJson: String? = nil,
        status: Status = .queued,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        errorMessage: String? = nil,
        attemptCount: Int = 0,
        serverMessageId: Int64? = nil
    ) {
        self.localId = localId
        self.username = username
        self.conversationKey = conversationKey
        self.flashNoteId = flashNoteId
        self.peerUserId = peerUserId
        self.clientRequestId = clientRequestId
        self.mediaType = mediaType
        self.content = content
        self.localFilePath = localFilePath
        self.remoteUrl = remoteUrl
        self.fileName = fileName
        self.fileSize = fileSize
        self.mediaDuration = mediaDuration
        self.processedFilePath = processedFilePath
        self.thumbnailUrl = thumbnailUrl
        self.payloadJson = payloadJson
        self.status = status
        self.createdAt = createdAt
        self.errorMessage = errorMessage
        self.attemptCount = attemptCount
        self.serverMessageId = serverMessageId
    }

    /// `pending_messages` 表所有列名（与 SQL DDL 顺序对齐，方便 SELECT * 直接 rowMapper）。
    public static let allColumns: String = """
        local_id, username, conversation_key, flash_note_id, peer_user_id, client_request_id,
        media_type, content, local_file_path, remote_url, file_name, file_size, media_duration,
        processed_file_path, thumbnail_url, payload_json, status, created_at, error_message,
        attempt_count, server_message_id
    """
}
