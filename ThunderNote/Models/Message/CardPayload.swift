import Foundation

/// 复合卡片消息的 payload，与服务端 `com.flashnote.message.entity.CardPayload` 对齐。
/// 后端字段：cardType / title / summary / items[]，items 的字段名为 type / url 等。
public struct CardPayload: Codable, Sendable, Equatable {
    public let cardType: String?
    public let title: String?
    public let summary: String?
    public let items: [CardItem]?

    public init(
        cardType: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        items: [CardItem]? = nil
    ) {
        self.cardType = cardType
        self.title = title
        self.summary = summary
        self.items = items
    }

    /// 主要的卡片类型常量。
    /// - `MESSAGE_COLLECTION`：merge 历史消息生成（服务端 `mergeMessages`）。
    /// - `COMPOSITE_MEDIA`：直接基于预上传媒体的新建卡片（服务端 `createCompositeMessage`）。
    public enum CardType {
        public static let messageCollection = "MESSAGE_COLLECTION"
        public static let compositeMedia = "COMPOSITE_MEDIA"
    }
}

public struct CardItem: Codable, Sendable, Equatable, Identifiable {
    public let originalMsgId: Int64?
    /// 服务端字段名 `type`（image / video / audio / file / TEXT / IMAGE / VIDEO...）；
    /// 本地用 `mediaType` 命名以贴近 `Message.mediaType`。
    public let mediaType: String?
    public let content: String?
    /// 服务端字段名 `url`（objectName 形如 `<userId>/<uuid>.<ext>`）。
    /// 本地用 `mediaUrl` 命名以贴近 `Message.mediaUrl`。
    public let mediaUrl: String?
    public let thumbnailUrl: String?
    public let fileName: String?
    public let fileSize: Int64?
    /// 服务端实际没有 `mediaDuration`，仅用于客户端展示视频时长；解码时会兜底为 nil。
    public let mediaDuration: Int?
    public let senderId: Int64?
    public let role: String?

    public var id: String {
        if let originalMsgId, originalMsgId > 0 { return "msg:\(originalMsgId)" }
        if let mediaUrl, !mediaUrl.isEmpty { return "obj:\(mediaUrl)" }
        return UUID().uuidString
    }

    public init(
        originalMsgId: Int64? = nil,
        mediaType: String? = nil,
        content: String? = nil,
        mediaUrl: String? = nil,
        thumbnailUrl: String? = nil,
        fileName: String? = nil,
        fileSize: Int64? = nil,
        mediaDuration: Int? = nil,
        senderId: Int64? = nil,
        role: String? = nil
    ) {
        self.originalMsgId = originalMsgId
        self.mediaType = mediaType
        self.content = content
        self.mediaUrl = mediaUrl
        self.thumbnailUrl = thumbnailUrl
        self.fileName = fileName
        self.fileSize = fileSize
        self.mediaDuration = mediaDuration
        self.senderId = senderId
        self.role = role
    }

    enum CodingKeys: String, CodingKey {
        case originalMsgId
        case mediaType = "type"
        case content
        case mediaUrl = "url"
        case thumbnailUrl
        case fileName
        case fileSize
        case mediaDuration
        case senderId
        case role
    }

    /// 解析媒体类型为强类型枚举，便于 UI 分发；与 Android `MessageMediaType` 对齐。
    public var resolvedMediaType: MessageMediaType {
        guard let raw = mediaType else { return .file }
        if let value = MessageMediaType(rawValue: raw.uppercased()) {
            return value
        }
        // 服务端可能返回小写 image / video / audio / file
        switch raw.lowercased() {
        case "image": return .image
        case "video": return .video
        case "audio": return .audio
        case "file":  return .file
        case "composite": return .composite
        case "text":  return .text
        default:      return .file
        }
    }
}
