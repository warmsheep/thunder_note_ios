import Foundation

/// 与后端 `FlashNote` 实体保持字段名一致（与 Android `FlashNote.java` 字段对齐）。
/// `id == -1` 是收集箱（Inbox）虚拟节点；该 id 在所有需要 inbox 行为的判断里都引用 `Self.inboxId`。
public struct FlashNote: Codable, Sendable, Equatable, Identifiable {
    public static let inboxId: Int64 = -1

    public var id: Int64
    public var userId: Int64?
    public var title: String?
    public var icon: String?
    public var content: String?
    /// 后端在 list 接口里聚合该闪记最新一条消息预览，媒体类型会以
    /// `[图片] / [视频] / [语音] / [文件]` 占位字符串返回。
    public var latestMessage: String?
    /// MVP 约定为单一合集 / 分类名称；可为空。
    public var tags: String?
    public var deleted: Bool?
    public var pinned: Bool?
    public var hidden: Bool?
    public var inbox: Bool?
    /// ISO 8601 / LocalDateTime 字符串。先按字符串保留，UI 层按需解析。
    public var createdAt: String?
    public var updatedAt: String?

    public init(
        id: Int64,
        userId: Int64? = nil,
        title: String? = nil,
        icon: String? = nil,
        content: String? = nil,
        latestMessage: String? = nil,
        tags: String? = nil,
        deleted: Bool? = nil,
        pinned: Bool? = nil,
        hidden: Bool? = nil,
        inbox: Bool? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.icon = icon
        self.content = content
        self.latestMessage = latestMessage
        self.tags = tags
        self.deleted = deleted
        self.pinned = pinned
        self.hidden = hidden
        self.inbox = inbox
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isInbox: Bool {
        id == Self.inboxId || inbox == true
    }

    public var isPinned: Bool {
        pinned == true
    }

    public var isHidden: Bool {
        hidden == true
    }

    public var displayTitle: String {
        if isInbox { return "收集箱" }
        if let title, !title.isEmpty { return title }
        return "未命名闪记"
    }

    public var displayIcon: String {
        if let icon, !icon.isEmpty { return icon }
        if isInbox { return "📥" }
        return "📝"
    }
}
