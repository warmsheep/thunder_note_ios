import Foundation

/// D2-I7-04 本地 conversation_key 计算工具，与 Android `util.ConversationKeyUtil` 对齐：
/// - 闪记会话：`forFlashNote(id) = id`（包含 `id == -1` 收集箱）
/// - 联系人会话：`forContact(peerUserId) = -1_000_000_000 - |peerUserId|`，避免与正向闪记 id 冲突
///
/// 用于 `pending_messages.conversation_key` / `messages_local.conversation_key`
/// 字段计算；同一条消息无论从哪一端进入本地，都应得到相同的 key。
public enum ConversationKeyResolver {
    public static let inboxFlashNoteId: Int64 = -1
    public static let contactKeyBase: Int64 = -1_000_000_000

    public static func forFlashNote(_ flashNoteId: Int64) -> Int64 {
        flashNoteId
    }

    public static func forContact(_ peerUserId: Int64) -> Int64 {
        contactKeyBase - abs(peerUserId)
    }

    /// 与 Android `resolve(flashNoteId, peerUserId)` 等价：peer 优先，闪记次之。
    public static func resolve(flashNoteId: Int64?, peerUserId: Int64?) -> Int64? {
        if let peer = peerUserId, peer > 0 {
            return forContact(peer)
        }
        if let flash = flashNoteId, flash != 0 {
            return forFlashNote(flash)
        }
        return nil
    }

    /// 给从服务端 pull 下来的 `Message` 计算本地 conversation_key。
    /// 关键约束：同一个会话的「发出」与「收到」消息必须落到同一个 key。
    /// - 闪记 / 收集箱（`flashNoteId != 0`）直接 `forFlashNote`；
    /// - 私聊：基于 `currentUserId` 把「不是自己」的那一端当作 peer，再 `forContact`；
    /// - `currentUserId` 缺失时兜底用 `receiverId`（适用于发送方场景）。
    public static func resolveForMessage(_ message: Message, currentUserId: Int64?) -> Int64? {
        if let flash = message.flashNoteId, flash != 0 {
            return forFlashNote(flash)
        }
        if let cur = currentUserId,
           let sender = message.senderId,
           let receiver = message.receiverId {
            let peer = cur == sender ? receiver : sender
            if peer > 0 { return forContact(peer) }
        }
        if let receiver = message.receiverId, receiver > 0 {
            return forContact(receiver)
        }
        return nil
    }
}

public extension ConversationKey {
    /// 持久化用的 conversation_key（与 Android 一致）。
    var persistenceKey: Int64 {
        switch self {
        case .flashNote(let id): return ConversationKeyResolver.forFlashNote(id)
        case .peer(let id):      return ConversationKeyResolver.forContact(id)
        }
    }
}
