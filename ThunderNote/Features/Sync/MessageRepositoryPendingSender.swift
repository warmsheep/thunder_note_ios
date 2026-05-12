import Foundation

/// D2-I7-05 Step 2B：把 `PendingMessageLocal` 翻译成 `Message` 并通过
/// `MessageRepository.send(...)` 真正发送。
///
/// 与 Android `PendingMessageDispatcher.sendPendingMessage()` 路径对齐：
/// - 文本消息：mediaType=TEXT，content 必填
/// - 媒体消息：要求 PendingMessage 已经走过上传链路，`remoteUrl` 必须非空（媒体上传由
///   `FileRepository` 在更上游完成；本 sender 不负责上传媒体，避免与 ChatViewModel 现有
///   乐观显示路径打架）
/// - 卡片消息：payloadJson 字段透传给后端（当前后端 send 走 `POST /api/messages`，
///   不接受 payload，COMPOSITE 走 `/api/messages/composite`；卡片消息暂不接 PendingMessage 链路）
///
/// 错误返回给 SyncEngine 后会触发 `attemptCount += 1` 与 FAILED 标记。
public struct MessageRepositoryPendingSender: PendingMessageSender {
    private let messageRepository: MessageRepository

    public init(messageRepository: MessageRepository) {
        self.messageRepository = messageRepository
    }

    public func send(_ pending: PendingMessageLocal) async throws -> Int64? {
        let message = try Self.message(from: pending)
        let saved = try await messageRepository.send(message)
        // D2-I7-05 Step 2B：把已确认消息写回本地表，让 ChatViewModel
        // 通过 conversationChanged → mergeLocalMessages 自动刷新为 sent。
        var confirmed = message
        confirmed.id = saved.id
        messageRepository.upsertLocalMessage(confirmed)
        return saved.id
    }

    /// PendingMessage → Message 的纯函数映射。抽出来便于单测。
    static func message(from pending: PendingMessageLocal) throws -> Message {
        let mediaType = pending.mediaType ?? MessageMediaType.text.rawValue
        // 文本必须有 content
        if mediaType == MessageMediaType.text.rawValue, (pending.content ?? "").isEmpty {
            throw APIError.business(code: -1, message: "文本消息内容为空")
        }
        // 媒体必须已上传（remoteUrl 非空）
        if mediaType != MessageMediaType.text.rawValue,
           (pending.remoteUrl ?? "").isEmpty {
            throw APIError.business(code: -1, message: "媒体未上传完成，无法发送")
        }
        return Message(
            id: pending.serverMessageId,
            senderId: nil, // 后端按 token 解析 senderId，客户端不需要传
            receiverId: pending.peerUserId,
            content: pending.content,
            readStatus: nil,
            flashNoteId: pending.flashNoteId,
            clientRequestId: pending.clientRequestId,
            role: nil,
            createdAt: nil,
            mediaType: mediaType,
            mediaUrl: pending.remoteUrl,
            mediaDuration: pending.mediaDuration.map { Int($0) },
            thumbnailUrl: pending.thumbnailUrl,
            fileName: pending.fileName,
            fileSize: pending.fileSize,
            payload: nil
        )
    }
}
