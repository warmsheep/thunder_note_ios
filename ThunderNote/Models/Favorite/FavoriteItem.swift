import Foundation

/// 收藏条目（与 Android `FavoriteItem.java` 字段对齐）。
/// 后端约定：当收藏消息属于收集箱（`flashNoteId == -1`），会额外返回
/// `flashNoteTitle="收集箱"`、`flashNoteIcon="📥"`。
public struct FavoriteItem: Codable, Sendable, Equatable, Identifiable {
    public var id: Int64
    public var messageId: Int64?
    public var flashNoteId: Int64?
    public var flashNoteTitle: String?
    public var flashNoteIcon: String?
    public var role: String?
    public var content: String?
    public var mediaType: String?
    public var mediaUrl: String?
    public var fileName: String?
    public var fileSize: Int64?
    public var mediaDuration: Int?
    public var favoritedAt: String?
    public var messageCreatedAt: String?
    public var payload: CardPayload?

    public init(
        id: Int64,
        messageId: Int64? = nil,
        flashNoteId: Int64? = nil,
        flashNoteTitle: String? = nil,
        flashNoteIcon: String? = nil,
        role: String? = nil,
        content: String? = nil,
        mediaType: String? = nil,
        mediaUrl: String? = nil,
        fileName: String? = nil,
        fileSize: Int64? = nil,
        mediaDuration: Int? = nil,
        favoritedAt: String? = nil,
        messageCreatedAt: String? = nil,
        payload: CardPayload? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.flashNoteId = flashNoteId
        self.flashNoteTitle = flashNoteTitle
        self.flashNoteIcon = flashNoteIcon
        self.role = role
        self.content = content
        self.mediaType = mediaType
        self.mediaUrl = mediaUrl
        self.fileName = fileName
        self.fileSize = fileSize
        self.mediaDuration = mediaDuration
        self.favoritedAt = favoritedAt
        self.messageCreatedAt = messageCreatedAt
        self.payload = payload
    }

    public var hasFlashNote: Bool {
        flashNoteId != nil
    }

    public var resolvedMediaType: MessageMediaType {
        MessageMediaType.resolve(mediaType)
    }

    public var displayTitle: String {
        if let flashNoteTitle, !flashNoteTitle.isEmpty {
            return flashNoteTitle
        }
        return "未关联闪记"
    }

    public var displayIcon: String {
        if let flashNoteIcon, !flashNoteIcon.isEmpty {
            return flashNoteIcon
        }
        return "⭐️"
    }

    public var displayPreview: String {
        if let content, !content.isEmpty { return content }
        switch resolvedMediaType {
        case .image: return "[图片]"
        case .video: return "[视频]"
        case .audio: return "[语音]"
        case .file: return fileName.map { "[文件] \($0)" } ?? "[文件]"
        case .composite: return "[卡片]"
        default: return ""
        }
    }
}
