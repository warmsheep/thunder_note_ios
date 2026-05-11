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
    /// `D2-I3-16` 多选模式开关。进入后 MessageBubble 显示 checkbox。
    @Published public private(set) var isMultiSelectMode: Bool = false
    /// `D2-I3-16` 当前多选选中的远端消息 id 集合。
    @Published public private(set) var selectedRemoteIds: Set<Int64> = []
    /// `D2-I3-17` 合并卡片标题输入 sheet 显示状态。
    @Published public var presentMergeSheet: Bool = false
    /// `D2-I3-03` 加载更早消息时的 prepend 锚点 messageId；UI 收到变化后会
    /// 把滚动位置稳定在该 id 对应气泡（避免视觉跳顶）。
    @Published public private(set) var prependAnchorMessageId: Int64? = nil

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
    private let scrollAnchorStore: ChatScrollAnchorStore?
    private var nextPage: Int = 1
    /// `D2-I3-04` 进入会话时根据 anchorStore 读出的恢复目标，加载首页后用于定位。
    private var pendingRestoreAnchorId: Int64? = nil
    /// D2-I7-04 Step 2D-2 订阅 MessageRepository 的会话变更事件。
    private var conversationChangedCancellable: AnyCancellable?

    public init(
        configuration: Configuration,
        messageRepository: MessageRepository,
        session: AuthSession,
        draftStore: DraftStore,
        favoriteRepository: FavoriteRepository? = nil,
        favoriteRegistry: FavoriteIdRegistry? = nil,
        attachmentService: AttachmentSendingService? = nil,
        mediaPreloader: MessageMediaPreloader? = nil,
        scrollAnchorStore: ChatScrollAnchorStore? = nil
    ) {
        self.configuration = configuration
        self.messageRepository = messageRepository
        self.favoriteRepository = favoriteRepository
        self.favoriteRegistry = favoriteRegistry
        self.attachmentService = attachmentService
        self.mediaPreloader = mediaPreloader
        self.session = session
        self.draftStore = draftStore
        self.scrollAnchorStore = scrollAnchorStore
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
            // 仅在 loadInitial 之前读取 anchor，避免重新进入时覆盖最新尾部位置。
            if configuration.targetMessageId == nil {
                pendingRestoreAnchorId = scrollAnchorStore?.anchor(for: configuration.key)
            }
            await loadInitial()
        }
        // 草稿恢复：onAppear 触发，避免初始化阶段尚未发布的状态导致丢字。
        let saved = draftStore.get(configuration.key)
        if inputText.isEmpty && !saved.isEmpty {
            inputText = saved
        }
        // D2-I7-04 Step 2D-2 订阅本地变更：每次 SyncCoordinator pull 落库后会推一轮，
        // 这里重读 `listLocalMessages` 并 merge 进当前 items（保留 pending / failed）。
        if conversationChangedCancellable == nil {
            conversationChangedCancellable = messageRepository
                .conversationChanged(for: configuration.key)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.mergeLocalMessages()
                }
        }
    }

    public func onDisappear() {
        // 持久化当前草稿到内存级 store。
        draftStore.set(configuration.key, text: inputText)
        // D2-I3-04：离开会话时把当前已确认的最尾部消息 id 写回 anchor。
        if let tail = items.reversed().first(where: { ($0.remoteId ?? 0) > 0 })?.remoteId {
            scrollAnchorStore?.setAnchor(tail, for: configuration.key)
        }
    }

    // MARK: - 加载

    public func loadInitial() async {
        loadState = .loading
        nextPage = 1
        // D2-I7-04 Step 2D-2 离线优先：先用 messages_local 把 items 立即显示出来，
        // 避免网络慢时空白；服务器返回后再覆盖（与 Android `getMessages` LiveData 体感等价）。
        let localSnapshot = messageRepository.listLocalMessages(
            key: configuration.key,
            limit: configuration.pageSize
        )
        if !localSnapshot.isEmpty {
            items = Self.sort(localSnapshot.map { Self.makeItem(from: $0) })
            loadState = .loaded
        }
        do {
            let page = try await messageRepository.listMessages(
                key: configuration.key,
                page: 1,
                limit: configuration.pageSize
            )
            let messages = page.safeRecords.map { Self.makeItem(from: $0) }
            // 后端默认 desc 返回（最新在前），UI 按 ascending 展示
            items = Self.mergePreservingPending(network: messages, current: items)
            hasMoreOlder = page.hasMore
            nextPage = Int(page.safeCurrent) + 1
            loadState = .loaded
            // 预加载最近的 image / video 缩略图
            if let preloader = mediaPreloader {
                let snapshot = items
                Task.detached { await preloader.preload(items: snapshot, limit: 5) }
            }
            await tryScrollToInitialTarget()
            // D2-I3-04：若没有 targetMessageId 且 anchor 命中页面，触发滚动恢复。
            await tryRestoreScrollAnchor()
        } catch let api as APIError {
            // 拿到本地快照时网络失败不掉进 error 态，给个 toast 提示即可。
            if items.isEmpty {
                loadState = .error(api.displayMessage)
            } else {
                transientMessage = api.displayMessage
                loadState = .loaded
            }
        } catch {
            if items.isEmpty {
                loadState = .error(error.localizedDescription)
            } else {
                transientMessage = error.localizedDescription
                loadState = .loaded
            }
        }
    }

    /// 收到 `conversationChanged` 事件后用本地表覆盖确认消息部分，保留 pending / failed。
    private func mergeLocalMessages() {
        let local = messageRepository.listLocalMessages(
            key: configuration.key,
            limit: max(configuration.pageSize, items.count)
        )
        guard !local.isEmpty else { return }
        let networkItems = local.map { Self.makeItem(from: $0) }
        items = Self.mergePreservingPending(network: networkItems, current: items)
    }

    /// 把网络 / 本地表的确认消息合并到当前 items，**保留** clientRequestId 未被服务端确认的
    /// pending / failed 项（避免后台 pull 把刚发出去还没拿到 id 的乐观消息冲掉）。
    static func mergePreservingPending(
        network: [ChatMessageItem],
        current: [ChatMessageItem]
    ) -> [ChatMessageItem] {
        let networkClientIds = Set(network.compactMap { $0.clientRequestId })
        let pendingTail = current.filter { item in
            switch item.status {
            case .sent: return false
            case .pending, .failed:
                // 已被服务端确认（clientRequestId 出现在网络结果里）就不再保留 pending 副本
                if let cid = item.clientRequestId, networkClientIds.contains(cid) {
                    return false
                }
                return true
            }
        }
        return sort(network + pendingTail)
    }

    /// 进入会话且首屏加载完成后，尝试按上次离开时的 anchor 把视图滚回去。
    /// 若首页中没有该消息，则不强行翻页（避免和 targetMessageId 冲突，也避免对新消息很多时的体感不准）。
    private func tryRestoreScrollAnchor() async {
        guard configuration.targetMessageId == nil,
              let anchorId = pendingRestoreAnchorId else { return }
        defer { pendingRestoreAnchorId = nil }
        if items.contains(where: { $0.remoteId == anchorId }) {
            // 锚点命中时静默 scroll（不闪烁），保持「上次看到这里」体感。
            scrollTargetMessageId = anchorId
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

    /// 触底加载更早的一页。
    /// D2-I3-03 prepend 偏移补正：发布 `prependAnchorMessageId`（旧 items 的第一条 remoteId），
    /// MessageListView 收到后会用 `scrollTo(anchor: .top)` 把锚点对齐回原位置，避免视觉跳顶。
    public func loadMoreOlder() async {
        guard !isLoadingMore, hasMoreOlder else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        // 记录加载前的顶部锚点：取当前 items 中第一条已确认消息的 remoteId。
        let preTopAnchorId: Int64? = items.first(where: { ($0.remoteId ?? 0) > 0 })?.remoteId
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
            // 发布 prepend anchor：UI 收到后 scrollTo(preTopAnchorId, anchor:.top)
            if let preTopAnchorId {
                prependAnchorMessageId = preTopAnchorId
            }
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    /// View 完成 prepend 偏移补正后调用，清除锚点避免重复触发。
    public func didConsumePrependAnchor() {
        prependAnchorMessageId = nil
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
                messageRepository.removeLocalMessages(ids: [remoteId])
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

    // MARK: - 多选模式（D2-I3-16）

    /// 进入多选模式，默认勾选触发项（仅已确认消息可选）。
    public func enterMultiSelect(initial item: ChatMessageItem? = nil) {
        isMultiSelectMode = true
        selectedRemoteIds.removeAll()
        if let item, let remoteId = item.remoteId, remoteId > 0 {
            selectedRemoteIds.insert(remoteId)
        }
    }

    /// 退出多选模式，清空选区。
    public func exitMultiSelect() {
        isMultiSelectMode = false
        selectedRemoteIds.removeAll()
    }

    /// 切换某条消息的多选状态。只对已确认消息生效。
    public func toggleSelection(_ item: ChatMessageItem) {
        guard let remoteId = item.remoteId, remoteId > 0 else { return }
        if selectedRemoteIds.contains(remoteId) {
            selectedRemoteIds.remove(remoteId)
        } else {
            selectedRemoteIds.insert(remoteId)
        }
    }

    /// 当前选区下的已确认消息（按 items 当前顺序）。
    public var selectedItems: [ChatMessageItem] {
        items.filter { item in
            guard let remoteId = item.remoteId else { return false }
            return selectedRemoteIds.contains(remoteId)
        }
    }

    /// 批量删除选中消息。成功后退出多选。
    public func deleteSelected() async {
        let ids = Array(selectedRemoteIds)
        guard !ids.isEmpty else { return }
        do {
            try await messageRepository.deleteBatch(ids: ids)
            items.removeAll { item in
                guard let remoteId = item.remoteId else { return false }
                return selectedRemoteIds.contains(remoteId)
            }
            messageRepository.removeLocalMessages(ids: ids)
            exitMultiSelect()
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    // MARK: - 合并卡片（D2-I3-17）

    /// 弹出合并卡片标题输入面板。仅在多选 ≥1 时生效；合并后退出多选并把卡片插入会话。
    public func openMergeSheet() {
        guard !selectedRemoteIds.isEmpty else {
            transientMessage = "请先选择至少一条消息"
            return
        }
        presentMergeSheet = true
    }

    /// 提交合并。`title` 必填、长度 ≤ 50；服务端会校验 messageIds ≤ 50 / 同一会话。
    public func mergeSelected(title rawTitle: String) async {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            transientMessage = "请输入卡片标题"
            return
        }
        guard title.count <= 50 else {
            transientMessage = "卡片标题最多 50 字"
            return
        }
        // 排序：与 Android `ChatMultiSelectHelper.mergeSelected` 等价 —— 按消息 id 升序
        let ids = selectedRemoteIds.sorted()
        guard !ids.isEmpty else { return }
        guard let userId = currentUserId else {
            transientMessage = "登录态已失效，请重新登录"
            return
        }
        let request = MessageMergeRequest(
            title: title,
            messageIds: ids,
            flashNoteId: configuration.key.flashNoteIdForRequest,
            receiverId: peerReceiverId(currentUserId: userId)
        )
        do {
            let confirmed = try await messageRepository.merge(request)
            // 把卡片消息插入到当前 items（已确认状态）
            let cardItem = Self.makeItem(from: confirmed)
            var newItems = items
            newItems.append(cardItem)
            items = Self.sort(newItems)
            messageRepository.upsertLocalMessage(confirmed)
            presentMergeSheet = false
            exitMultiSelect()
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    /// 联系人会话的 receiverId（非联系人会话返回 nil）。merge / composite 用。
    private func peerReceiverId(currentUserId: Int64) -> Int64? {
        if case .peer(let peerId) = configuration.key { return peerId }
        return nil
    }

    /// 卡片编辑器：用客户端预上传的 items 直接新建 COMPOSITE 卡片。
    /// 由 `CardEditorViewModel` 调用；卡片新建成功后插入会话末尾。
    public func submitComposite(_ request: CompositeMessageRequest) async -> Bool {
        do {
            let confirmed = try await messageRepository.createComposite(request)
            let cardItem = Self.makeItem(from: confirmed)
            var newItems = items
            newItems.append(cardItem)
            items = Self.sort(newItems)
            messageRepository.upsertLocalMessage(confirmed)
            return true
        } catch let api as APIError {
            transientMessage = api.displayMessage
            return false
        } catch {
            transientMessage = error.localizedDescription
            return false
        }
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
        // D2-I7-04 Step 2D-2 把已确认的消息同步到本地表，让其他端 pull 时不需要再覆盖一次。
        messageRepository.upsertLocalMessage(confirmed)
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
