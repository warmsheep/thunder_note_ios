import Foundation

/// 主 App 启动 / 切回前台时扫描 ShareInbox，把待消费条目交给 UI 层。
/// 消费成功（用户选择目标并发送）后，调用 `markConsumed(_:)` 从 inbox 删除该条目。
@MainActor
public final class ShareInboxConsumer: ObservableObject {
    @Published public private(set) var pendingEntries: [ShareInboxEntry] = []

    public let store: ShareInboxStore?

    public init(store: ShareInboxStore?) {
        self.store = store
    }

    /// 重新扫描 inbox（会覆盖当前 `pendingEntries`）。
    public func scan() {
        guard let store else {
            pendingEntries = []
            return
        }
        pendingEntries = store.allEntries()
    }

    /// 处理完一条（发送成功 / 用户放弃）后调用。
    public func markConsumed(_ entry: ShareInboxEntry) {
        guard let store else { return }
        try? store.remove(id: entry.id)
        pendingEntries.removeAll { $0.id == entry.id }
    }

    /// 全部丢弃（测试 / 重置场景）。
    public func clearAll() {
        guard let store else {
            pendingEntries = []
            return
        }
        try? store.clearAll()
        pendingEntries = []
    }

    /// 解析条目对应本地附件 URL（仅 image/video/file）。
    public func attachmentURL(for entry: ShareInboxEntry) -> URL? {
        guard let store, let relative = entry.relativeFilePath else { return nil }
        return store.resolveAttachmentURL(relativePath: relative)
    }
}
