import Foundation

/// 三种会话模式的统一 key（与 Android `ConversationKeyUtil` 对齐）：
/// - `flashNote(id)`: 普通闪记（包含 `id == -1` 的收集箱）
/// - `peer(userId)`: 联系人会话
public enum ConversationKey: Hashable, Sendable, Codable, Identifiable {
    case flashNote(Int64)
    case peer(Int64)

    public var id: String { descriptor }

    public var descriptor: String {
        switch self {
        case .flashNote(let id): return "flash:\(id)"
        case .peer(let id):      return "peer:\(id)"
        }
    }

    public var isInbox: Bool {
        if case .flashNote(FlashNote.inboxId) = self { return true }
        return false
    }

    public var isPeer: Bool {
        if case .peer = self { return true }
        return false
    }

    /// 拉取消息时按需要传给后端的 `flashNoteId`（不适用 → nil）。
    public var flashNoteIdForRequest: Int64? {
        if case .flashNote(let id) = self { return id }
        return nil
    }

    /// 拉取消息时按需要传给后端的 `peerUserId`（不适用 → nil）。
    public var peerUserIdForRequest: Int64? {
        if case .peer(let id) = self { return id }
        return nil
    }
}
