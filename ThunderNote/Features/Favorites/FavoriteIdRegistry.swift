import Foundation
import Combine

/// 全局已收藏 messageId 集合：
/// - 收藏列表加载后会把所有项写入；
/// - 聊天页菜单切换收藏后会增 / 删；
/// - 各 ChatViewModel 通过 publisher 订阅，统一更新本地 isFavorited 标记。
@MainActor
public final class FavoriteIdRegistry: ObservableObject {
    @Published public private(set) var favoritedMessageIds: Set<Int64> = []

    public init() {}

    public func replaceAll(_ ids: [Int64]) {
        favoritedMessageIds = Set(ids)
    }

    public func add(_ messageId: Int64) {
        favoritedMessageIds.insert(messageId)
    }

    public func remove(_ messageId: Int64) {
        favoritedMessageIds.remove(messageId)
    }

    public func contains(_ messageId: Int64) -> Bool {
        favoritedMessageIds.contains(messageId)
    }

    public func clear() {
        favoritedMessageIds.removeAll()
    }
}
