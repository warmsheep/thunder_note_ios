import Foundation

/// 复合卡片消息的 payload。当前 MVP 仅占位，详细字段在 D2-I3-17 ~ I3-19 落地。
public struct CardPayload: Codable, Sendable, Equatable {
    public let title: String?
    public let summary: String?
    public let items: [CardItem]?

    public init(title: String? = nil, summary: String? = nil, items: [CardItem]? = nil) {
        self.title = title
        self.summary = summary
        self.items = items
    }
}

public struct CardItem: Codable, Sendable, Equatable {
    public let originalMsgId: Int64?
    public let mediaType: String?
    public let content: String?
    public let mediaUrl: String?
    public let thumbnailUrl: String?
    public let fileName: String?
    public let fileSize: Int64?
    public let mediaDuration: Int?

    public init(
        originalMsgId: Int64? = nil,
        mediaType: String? = nil,
        content: String? = nil,
        mediaUrl: String? = nil,
        thumbnailUrl: String? = nil,
        fileName: String? = nil,
        fileSize: Int64? = nil,
        mediaDuration: Int? = nil
    ) {
        self.originalMsgId = originalMsgId
        self.mediaType = mediaType
        self.content = content
        self.mediaUrl = mediaUrl
        self.thumbnailUrl = thumbnailUrl
        self.fileName = fileName
        self.fileSize = fileSize
        self.mediaDuration = mediaDuration
    }
}
