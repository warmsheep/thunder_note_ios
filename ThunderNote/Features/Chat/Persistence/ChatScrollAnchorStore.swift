import Foundation

/// 进入会话时恢复滚动位置（D2-I3-04）。
///
/// 与 Android `rememberRenderedTailState` 等价：每个 `ConversationKey` 维护一个
/// 「上次离开时停留的最尾部 messageId」。
/// - 进入会话时：若拿到 anchor，UI 滚动到对应 messageId；
/// - 拿不到 anchor / 是首次进入：滚到底；
/// - 离开会话时：把当前 items 的最末已确认消息 id 存下来。
///
/// 持久化采用 `UserDefaults`（key 命名 `tn.chat.anchor.<descriptor>`），轻量、
/// 跨 App 启动可恢复；不写复杂的 sessionStorage。
public final class ChatScrollAnchorStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, prefix: String = "tn.chat.anchor.") {
        self.defaults = defaults
        self.prefix = prefix
    }

    /// 读取上次记录的尾部 messageId；不存在或被清空时返回 nil。
    public func anchor(for key: ConversationKey) -> Int64? {
        lock.lock(); defer { lock.unlock() }
        let value = defaults.object(forKey: storageKey(for: key))
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let string = value as? String, let parsed = Int64(string) {
            return parsed
        }
        return nil
    }

    /// 把 messageId 作为 anchor 写回（已确认消息 id > 0 才写入）。
    public func setAnchor(_ messageId: Int64?, for key: ConversationKey) {
        lock.lock(); defer { lock.unlock() }
        let storage = storageKey(for: key)
        guard let messageId, messageId > 0 else {
            defaults.removeObject(forKey: storage)
            return
        }
        defaults.set(NSNumber(value: messageId), forKey: storage)
    }

    /// 清空指定会话的 anchor（消息被删除等场景）。
    public func clearAnchor(for key: ConversationKey) {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: storageKey(for: key))
    }

    /// 单测 / 切账号时清空所有 anchor。
    public func clearAll() {
        lock.lock(); defer { lock.unlock() }
        let allKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
    }

    private func storageKey(for key: ConversationKey) -> String {
        prefix + key.descriptor
    }
}
