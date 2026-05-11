import Foundation
import Combine

/// 内存级草稿存储（per `ConversationKey.descriptor`）。
/// 离开会话时调用 `set` 持久化；进入会话时 `get` 读取。
/// 当前为内存存储，重启 App 后清空，与 Android `ChatInputHelper` 默认行为对齐。
@MainActor
public final class DraftStore: ObservableObject {
    @Published public private(set) var drafts: [String: String] = [:]

    public init() {}

    public func get(_ key: ConversationKey) -> String {
        drafts[key.descriptor] ?? ""
    }

    public func set(_ key: ConversationKey, text: String) {
        let trimmed = text
        if trimmed.isEmpty {
            drafts.removeValue(forKey: key.descriptor)
        } else {
            drafts[key.descriptor] = trimmed
        }
    }

    public func clear(_ key: ConversationKey) {
        drafts.removeValue(forKey: key.descriptor)
    }
}
