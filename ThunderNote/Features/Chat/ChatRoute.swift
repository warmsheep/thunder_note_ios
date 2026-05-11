import Foundation

/// 用于 `NavigationStack.navigationDestination(for:)` 的会话路由值。
/// 含目标 `ConversationKey`、标题、可选 `flashNoteId`（驱动「打开会话自动 unhide」）。
public struct ChatRoute: Hashable, Sendable {
    public let key: ConversationKey
    public let title: String
    /// 仅 `flash:<id>` 且非收集箱时为非空；用于在 onAppear 触发 `unhideIfNeeded`。
    public let flashNoteId: Int64?
    /// 从收藏 / 搜索跳转时携带的目标 messageId，进入会话后用于精确定位。
    /// 当前 MVP 仅记录该值，真正的 `scrollToMessageId + 高亮` 在 D2-I3-05 落地。
    public let targetMessageId: Int64?

    public init(
        key: ConversationKey,
        title: String,
        flashNoteId: Int64?,
        targetMessageId: Int64? = nil
    ) {
        self.key = key
        self.title = title
        self.flashNoteId = flashNoteId
        self.targetMessageId = targetMessageId
    }
}
