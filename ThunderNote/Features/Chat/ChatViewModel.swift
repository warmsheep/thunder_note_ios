import Foundation
import Combine

/// 聊天页 ViewModel：复用一套逻辑覆盖三种 conversationKey
/// （`flash:<id>` / `peer:<userId>` / `flash:-1` 收集箱）。
@MainActor
public final class ChatViewModel: ObservableObject {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    public struct Configuration: Sendable {
        public let key: ConversationKey
        public let title: String
        public let pageSize: Int
        public init(key: ConversationKey, title: String, pageSize: Int = 20) {
            self.key = key
            self.title = title
            self.pageSize = pageSize
        }
    }

    @Published public private(set) var items: [ChatMessageItem] = []
    @Published public var inputText: String = ""
    @Published public private(set) var loadState: LoadState = .idle
    @Published public private(set) var isLoadingMore: Bool = false
    @Published public private(set) var hasMoreOlder: Bool = true
    @Published public private(set) var isSending: Bool = false
    @Published public var transientMessage: String? = nil

    public let configuration: Configuration
    public var key: ConversationKey { configuration.key }
    public var title: String {
        if configuration.key.isInbox { return "收集箱" }
        return configuration.title
    }

    private let messageRepository: MessageRepository
    private let session: AuthSession
    private let draftStore: DraftStore
    private var nextPage: Int = 1

    public init(
        configuration: Configuration,
        messageRepository: MessageRepository,
        session: AuthSession,
        draftStore: DraftStore
    ) {
        self.configuration = configuration
        self.messageRepository = messageRepository
        self.session = session
        self.draftStore = draftStore
        self.inputText = draftStore.get(configuration.key)
    }

    public var currentUserId: Int64? {
        if case .authenticated(let user) = session.state { return user.id }
        return nil
    }

    // MARK: - 生命周期

    public func onAppear() async {
        if case .idle = loadState {
            await loadInitial()
        }
        // 草稿恢复：onAppear 触发，避免初始化阶段尚未发布的状态导致丢字。
        let saved = draftStore.get(configuration.key)
        if inputText.isEmpty && !saved.isEmpty {
            inputText = saved
        }
    }

    public func onDisappear() {
        // 持久化当前草稿到内存级 store。
        draftStore.set(configuration.key, text: inputText)
    }

    // MARK: - 加载

    public func loadInitial() async {
        loadState = .loading
        nextPage = 1
        do {
            let page = try await messageRepository.listMessages(
                key: configuration.key,
                page: 1,
                limit: configuration.pageSize
            )
            let messages = page.safeRecords.map { Self.makeItem(from: $0) }
            // 后端默认 desc 返回（最新在前），UI 按 ascending 展示
            items = Self.sort(messages)
            hasMoreOlder = page.hasMore
            nextPage = Int(page.safeCurrent) + 1
            loadState = .loaded
        } catch let api as APIError {
            loadState = .error(api.displayMessage)
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    /// 触底加载更早的一页。当前以 `nextPage` 递增；后续 D2-I3-03 升级为
    /// 真正的「向上滚加载更早」。
    public func loadMoreOlder() async {
        guard !isLoadingMore, hasMoreOlder else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await messageRepository.listMessages(
                key: configuration.key,
                page: nextPage,
                limit: configuration.pageSize
            )
            let older = page.safeRecords.map { Self.makeItem(from: $0) }
            // 与 Android 行为对齐：去重合并
            var merged = items
            for item in older where !merged.contains(where: { $0.id == item.id }) {
                merged.append(item)
            }
            items = Self.sort(merged)
            hasMoreOlder = page.hasMore
            nextPage = Int(page.safeCurrent) + 1
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    public func refresh() async {
        await loadInitial()
    }

    // MARK: - 发送

    public func sendText() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        guard let userId = currentUserId else {
            transientMessage = "登录态已失效，请重新登录"
            return
        }
        isSending = true
        defer { isSending = false }

        let clientRequestId = UUID().uuidString
        let now = ISO8601DateFormatter().string(from: Date())
        var local = Message(
            id: nil,
            senderId: userId,
            receiverId: receiverIdForCurrentKey(currentUserId: userId),
            content: trimmed,
            flashNoteId: configuration.key.flashNoteIdForRequest,
            clientRequestId: clientRequestId,
            createdAt: now,
            mediaType: MessageMediaType.text.rawValue
        )
        let pendingItem = ChatMessageItem(
            clientRequestId: clientRequestId,
            remoteId: nil,
            status: .pending,
            message: local
        )
        items = Self.sort(items + [pendingItem])
        // 清空输入与草稿——成功失败都不再保留这条文本作为草稿
        inputText = ""
        draftStore.clear(configuration.key)

        do {
            let confirmed = try await messageRepository.send(local)
            replacePending(clientRequestId: clientRequestId, with: confirmed)
        } catch let api as APIError {
            local.id = nil
            updatePendingFailure(clientRequestId: clientRequestId, reason: api.displayMessage)
        } catch {
            updatePendingFailure(clientRequestId: clientRequestId, reason: error.localizedDescription)
        }
    }

    /// 失败消息重试：保留同一个 clientRequestId 重新发送。
    public func retry(_ item: ChatMessageItem) async {
        guard case .failed = item.status else { return }
        guard let clientRequestId = item.clientRequestId else { return }
        // 标记为 pending
        if let idx = items.firstIndex(where: { $0.clientRequestId == clientRequestId }) {
            items[idx].status = .pending
        }
        do {
            let confirmed = try await messageRepository.send(item.message)
            replacePending(clientRequestId: clientRequestId, with: confirmed)
        } catch let api as APIError {
            updatePendingFailure(clientRequestId: clientRequestId, reason: api.displayMessage)
        } catch {
            updatePendingFailure(clientRequestId: clientRequestId, reason: error.localizedDescription)
        }
    }

    // MARK: - 删除

    public func delete(_ item: ChatMessageItem) async {
        // 本地 pending / failed 消息直接删本地条目
        if let remoteId = item.remoteId, remoteId > 0 {
            do {
                try await messageRepository.delete(id: remoteId)
                items.removeAll { $0.id == item.id }
            } catch let api as APIError {
                transientMessage = api.displayMessage
            } catch {
                transientMessage = error.localizedDescription
            }
        } else {
            items.removeAll { $0.id == item.id }
        }
    }

    public func clearTransientMessage() {
        transientMessage = nil
    }

    // MARK: - Helpers

    private func receiverIdForCurrentKey(currentUserId: Int64) -> Int64? {
        switch configuration.key {
        case .flashNote: return currentUserId  // 闪记发送对端约定为自己（与 Android 等价）
        case .peer(let peerId): return peerId
        }
    }

    private func replacePending(clientRequestId: String, with confirmed: Message) {
        let item = ChatMessageItem(
            clientRequestId: confirmed.clientRequestId ?? clientRequestId,
            remoteId: confirmed.id,
            status: .sent,
            message: confirmed
        )
        if let idx = items.firstIndex(where: { $0.clientRequestId == clientRequestId }) {
            items[idx] = item
        } else {
            items.append(item)
        }
        items = Self.sort(items)
    }

    private func updatePendingFailure(clientRequestId: String, reason: String) {
        guard let idx = items.firstIndex(where: { $0.clientRequestId == clientRequestId }) else { return }
        items[idx].status = .failed(reason: reason)
    }

    private static func makeItem(from message: Message) -> ChatMessageItem {
        ChatMessageItem(
            clientRequestId: message.clientRequestId,
            remoteId: message.id,
            status: .sent,
            message: message
        )
    }

    /// 排序：按 `createdAt` 升序；createdAt 相同按 id 升序。pending（无 id）
    /// 默认排在尾部（用「9999-」哨兵 sortKey）。
    static func sort(_ source: [ChatMessageItem]) -> [ChatMessageItem] {
        source.sorted { lhs, rhs in
            if lhs.sortKey != rhs.sortKey { return lhs.sortKey < rhs.sortKey }
            return (lhs.remoteId ?? 0) < (rhs.remoteId ?? 0)
        }
    }
}
