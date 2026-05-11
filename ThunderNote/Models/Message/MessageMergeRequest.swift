import Foundation

/// `POST /api/messages/merge` 请求体（D2-I3-17）。
/// 服务端要求：title 非空、messageIds ≤ 50 条、flashNoteId / receiverId 二选一。
public struct MessageMergeRequest: Encodable, Sendable {
    public let title: String
    public let messageIds: [Int64]
    public let flashNoteId: Int64?
    public let receiverId: Int64?

    public init(
        title: String,
        messageIds: [Int64],
        flashNoteId: Int64?,
        receiverId: Int64?
    ) {
        self.title = title
        self.messageIds = messageIds
        self.flashNoteId = flashNoteId
        self.receiverId = receiverId
    }
}

/// `POST /api/messages/composite` 请求体（D2-I3-19 卡片编辑器）。
/// 服务端要求：title 非空且 ≤ 50 字符、items 1~9 条、每个 item.mediaUrl 必须是当前用户上传的 objectName。
public struct CompositeMessageRequest: Encodable, Sendable {
    public let title: String
    public let content: String?
    public let flashNoteId: Int64?
    public let receiverId: Int64?
    public let items: [Item]

    public init(
        title: String,
        content: String? = nil,
        flashNoteId: Int64?,
        receiverId: Int64?,
        items: [Item]
    ) {
        self.title = title
        self.content = content
        self.flashNoteId = flashNoteId
        self.receiverId = receiverId
        self.items = items
    }

    public struct Item: Encodable, Sendable {
        public let type: String
        public let mediaUrl: String
        public let thumbnailUrl: String?
        public let fileName: String?
        public let fileSize: Int64?
        public let content: String?

        public init(
            type: String,
            mediaUrl: String,
            thumbnailUrl: String? = nil,
            fileName: String? = nil,
            fileSize: Int64? = nil,
            content: String? = nil
        ) {
            self.type = type
            self.mediaUrl = mediaUrl
            self.thumbnailUrl = thumbnailUrl
            self.fileName = fileName
            self.fileSize = fileSize
            self.content = content
        }
    }
}
