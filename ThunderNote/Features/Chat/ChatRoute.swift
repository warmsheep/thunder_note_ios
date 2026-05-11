import Foundation

/// 用于 `NavigationStack.navigationDestination(for:)` 的会话路由值。
/// 含目标 `ConversationKey`、标题、可选 `flashNoteId`（驱动「打开会话自动 unhide」）。
public struct ChatRoute: Hashable, Sendable {
    public let key: ConversationKey
    public let title: String
    /// 仅 `flash:<id>` 且非收集箱时为非空；用于在 onAppear 触发 `unhideIfNeeded`。
    public let flashNoteId: Int64?

    public init(key: ConversationKey, title: String, flashNoteId: Int64?) {
        self.key = key
        self.title = title
        self.flashNoteId = flashNoteId
    }
}
