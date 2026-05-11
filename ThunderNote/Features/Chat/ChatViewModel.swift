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
        /// 从收藏 / 搜索跳转时携带的目标 messageId；只是一个语义标记，
        /// 真正的 `scrollToMessageId + 高亮` 在 D2-I3-05 阶段落地。
        public let targetMessageId: Int64?

        public init(
            key: ConversationKey,
            title: String,
            pageSize: Int = 20,
            targetMessageId: Int64? = nil
        ) {
            self.key = key
            self.title = title
            self.pageSize = pageSize
            self.targetMessageId = targetMessageId
        }
    }

    @Published public private(set) var items: [ChatMessageItem] = []
    @Published public var inputText: String = ""
    @Published public private(set) var loadState: LoadState = .idle
    @Published public private(set) var isLoadingMore: Bool = false
    @Published public private(set) var hasMoreOlder: Bool = true
    @Published public private(set) var isSending: Bool = false
    @Published public var transientMessage: String? = nil
    /// `D2-I3-05` 用：滚到指定 messageId + 高亮闪烁。`nil` 表示当前不需要滚动。
    @Published public private(set) var scrollTargetMessageId: Int64? = nil
    /// `D2-I3-05` 用：当前需要黄底高亮的消息（短暂闪烁 1.5s 后归零）。
    @Published public private(set) var highlightedMessageId: Int64? = nil

    public let configuration: Configuration
    public var key: ConversationKey { configuration.key }
    public var title: String {
        if configuration.key.isInbox { return "收集箱" }
        return configuration.title
    }

    private let messageRepository: MessageRepository
    private let favoriteRepository: FavoriteRepository?
    private let favoriteRegistry: FavoriteIdRegistry?
    private let attachmentService: AttachmentSendingService?
    private let mediaPreloader: MessageMediaPreloader?
    private let session: AuthSession
    private let draftStore: DraftStore
    private var nextPage: Int = 1

    public init(
        configuration: Configuration,
        messageRepository: MessageRepository,
        session: AuthSession,
        draftStore: DraftStore,
        favoriteRepository: FavoriteRepository? = nil,
        favoriteRegistry: FavoriteIdRegistry? = nil,
        attachmentService: AttachmentSendingService? = nil,
        mediaPreloader: MessageMediaPreloader? = nil
    ) {
        self.configuration = configuration
        self.messageRepository = messageRepository
        self.favoriteRepository = favoriteRepository
        self.favoriteRegistry = favoriteRegistry
        self.attachmentService = attachmentService
        self.mediaPreloader = mediaPreloader
        self.session = session
        self.draftStore = draftStore
        self.inputText = draftStore.get(configuration.key)
    }

    /// 当前消息是否已收藏（基于 `FavoriteIdRegistry`）。
    public func isFavorited(_ item: ChatMessageItem) -> Bool {
        guard let registry = favoriteRegistry, let remoteId = item.remoteId else { return false }
        return registry.contains(remoteId)
    }

    /// 切换收藏 / 取消收藏。仅对已确认（有 remoteId）消息生效。
    public func toggleFavorite(_ item: ChatMessageItem) async {
        guard let repository = favoriteRepository,
              let registry = favoriteRegistry,
              let remoteId = item.remoteId else {
            transientMessage = "消息尚未发送，暂不能收藏"
            return
        }
        let wasFavorited = registry.contains(remoteId)
        // 乐观更新
        if wasFavorited {
            registry.remove(remoteId)
        } else {
            registry.add(remoteId)
        }
        do {
            if wasFavorited {
                try await repository.unfavorite(messageId: remoteId)
            } else {
                _ = try await repository.favorite(messageId: remoteId)
            }
        } catch let api as APIError {
            // 回滚
            if wasFavorited {
                registry.add(remoteId)
            } else {
                registry.remove(remoteId)
            }
            transientMessage = api.displayMessage
        } catch {
            if wasFavorited {
                registry.add(remoteId)
            } else {
                registry.remove(remoteId)
            }
            transientMessage = error.localizedDescription
        }
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
            // 预加载最近的 image / video 缩略图
            if let preloader = mediaPreloader {
                let snapshot = items
                Task.detached { await preloader.preload(items: snapshot, limit: 5) }
            }
            await tryScrollToInitialTarget()
        } catch let api as APIError {
            loadState = .error(api.displayMessage)
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    /// 进入会话且首屏加载完成后，按 `configuration.targetMessageId` 尝试定位。
    /// 若当前页没找到，会沿 `loadMoreOlder()` 翻页（最多 5 页）继续找；都找不到则 toast。
    private func tryScrollToInitialTarget() async {
        guard let targetId = configuration.targetMessageId else { return }
        if items.contains(where: { $0.remoteId == targetId }) {
            triggerScroll(to: targetId)
            return
        }
        // 翻页搜索：避免无限翻历史，限制 5 页。
        var attempts = 0
        while attempts < 5 && hasMoreOlder {
            await loadMoreOlder()
            if items.contains(where: { $0.remoteId == targetId }) {
                triggerScroll(to: targetId)
                return
            }
            attempts += 1
        }
        transientMessage = "未找到该消息（可能已删除或过旧）"
    }

    /// 触发滚动 + 高亮闪烁（1.5s 后取消）。
    public func triggerScroll(to messageId: Int64) {
        scrollTargetMessageId = messageId
        highlightedMessageId = messageId
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                guard let self else { return }
                if self.highlightedMessageId == messageId {
                    self.highlightedMessageId = nil
                }
            }
        }
    }

    /// View 完成滚动后调用，清掉 scrollTarget 避免重复滚。
    public func didConsumeScrollTarget() {
        scrollTargetMessageId = nil
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

    // MARK: - 发送媒体消息（D2-I3-08 / 09 / 13）

    public func sendImage(localURL: URL) async {
        await sendAttachment(
            mediaType: .image,
            localContentDescription: "[图片]"
        ) { [attachmentService] in
            guard let attachmentService else { throw ChatVMError.attachmentServiceMissing }
            let outcome = try await attachmentService.uploadImage(sourceURL: localURL)
            return AttachmentResult(
                mediaUrl: outcome.mediaObjectName,
                thumbnailUrl: outcome.thumbnailObjectName,
                fileName: localURL.lastPathComponent,
                fileSize: nil,
                mediaDuration: nil
            )
        }
    }

    public func sendVideo(localURL: URL) async {
        await sendAttachment(
            mediaType: .video,
            localContentDescription: "[视频]"
        ) { [attachmentService] in
            guard let attachmentService else { throw ChatVMError.attachmentServiceMissing }
            let outcome = try await attachmentService.uploadVideo(sourceURL: localURL)
            return AttachmentResult(
                mediaUrl: outcome.mediaObjectName,
                thumbnailUrl: outcome.thumbnailObjectName,
                fileName: localURL.lastPathComponent,
                fileSize: nil,
                mediaDuration: outcome.durationSeconds
            )
        }
    }

    public func sendFile(localURL: URL) async {
        await sendAttachment(
            mediaType: .file,
            localContentDescription: "[文件] \(localURL.lastPathComponent)"
        ) { [attachmentService] in
            guard let attachmentService else { throw ChatVMError.attachmentServiceMissing }
            let outcome = try await attachmentService.uploadFile(sourceURL: localURL)
            return AttachmentResult(
                mediaUrl: outcome.mediaObjectName,
                thumbnailUrl: nil,
                fileName: outcome.fileName,
                fileSize: outcome.fileSize,
                mediaDuration: nil
            )
        }
    }

    private struct AttachmentResult {
        let mediaUrl: String
        let thumbnailUrl: String?
        let fileName: String?
        let fileSize: Int64?
        let mediaDuration: Int?
    }

    private enum ChatVMError: Error {
        case attachmentServiceMissing
    }

    private func sendAttachment(
        mediaType: MessageMediaType,
        localContentDescription: String,
        upload: @MainActor () async throws -> AttachmentResult
    ) async {
        guard let userId = currentUserId else {
            transientMessage = "登录态已失效，请重新登录"
            return
        }
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }

        let clientRequestId = UUID().uuidString
        let now = ISO8601DateFormatter().string(from: Date())
        var local = Message(
            id: nil,
            senderId: userId,
            receiverId: receiverIdForCurrentKey(currentUserId: userId),
            content: localContentDescription,
            flashNoteId: configuration.key.flashNoteIdForRequest,
            clientRequestId: clientRequestId,
            createdAt: now,
            mediaType: mediaType.rawValue
        )
        let pending = ChatMessageItem(
            clientRequestId: clientRequestId,
            remoteId: nil,
            status: .pending,
            message: local
        )
        items = Self.sort(items + [pending])

        do {
            let result = try await upload()
            local.mediaUrl = result.mediaUrl
            local.thumbnailUrl = result.thumbnailUrl
            local.fileName = result.fileName
            local.fileSize = result.fileSize
            local.mediaDuration = result.mediaDuration
            // 文本占位换成 nil（后端按 mediaType 走，content 通常空字符串即可）
            local.content = mediaType == .file ? local.content : nil
            let confirmed = try await messageRepository.send(local)
            replacePending(clientRequestId: clientRequestId, with: confirmed)
        } catch let api as APIError {
            updatePendingFailure(clientRequestId: clientRequestId, reason: api.displayMessage)
        } catch ChatVMError.attachmentServiceMissing {
            updatePendingFailure(clientRequestId: clientRequestId, reason: "尚未启用附件能力")
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
