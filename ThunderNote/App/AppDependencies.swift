import Foundation
import SwiftUI
import Combine

/// 顶层依赖容器：在 App 启动时构造一次。登录态变化触发 Repository 重建逻辑放在这里。
@MainActor
public final class AppDependencies: ObservableObject {
    public let serverConfigStore: ServerConfigStore
    public let serverConfigObservable: ServerConfigStoreObservable
    public let tokenStore: TokenStoring
    public let session: AuthSession
    public let apiClient: APIClient
    public let authRepository: AuthRepository
    public let authViewModel: AuthViewModel
    public let flashNoteRepository: FlashNoteRepository
    public let flashNoteListViewModel: FlashNoteListViewModel
    public let flashNoteSearchViewModel: FlashNoteSearchViewModel
    public let userRepository: UserRepository
    public let profileViewModel: ProfileViewModel
    public let profileStatsViewModel: ProfileStatsViewModel
    public let gestureLockStore: GestureLockStoring
    public let database: TNDatabase
    public let syncMetaDao: SyncMetaDao
    public let pendingMessageDao: PendingMessageDao
    public let messageLocalDao: MessageLocalDao
    public let syncRepository: SyncRepository
    public let syncEngine: SyncEngine
    public let syncCoordinator: SyncCoordinator
    public let messageRepository: MessageRepository
    public let draftStore: DraftStore
    public let collectionRepository: CollectionRepository
    public let contactRepository: ContactRepository
    public let collectionsViewModel: CollectionsViewModel
    public let contactsViewModel: ContactsViewModel
    public let favoriteRepository: FavoriteRepository
    public let favoriteRegistry: FavoriteIdRegistry
    public let favoritesViewModel: FavoritesViewModel
    public let fileRepository: FileRepository
    public let mediaUrlResolver: MediaUrlResolver
    public let shareInboxStore: ShareInboxStore?
    public let shareInboxConsumer: ShareInboxConsumer
    public let attachmentSendingService: AttachmentSendingService
    public let mediaPreloader: MessageMediaPreloader
    public let scrollAnchorStore: ChatScrollAnchorStore
    public let authenticatedImageLoader: AuthenticatedImageLoader

    /// D2-I7 监听 AuthSession.state，在切到 authenticated 时触发 bootstrapIfNeeded。
    private var sessionStateCancellable: AnyCancellable? = nil

    public init() {
        let serverConfigStore = ServerConfigStore()
        let tokenStore = KeychainTokenStore()
        let session = AuthSession(tokenStore: tokenStore)
        // D2-I7 SQLite 数据库：Library/Application Support/tn/tn.sqlite3。
        // 打开 / migration 失败时让 App 立刻崩，避免静默走没有本地表的不可控路径。
        let appSupportRoot = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
        let dbURL = appSupportRoot
            .appendingPathComponent("tn", isDirectory: true)
            .appendingPathComponent("tn.sqlite3")
        let database: TNDatabase
        do {
            database = try TNDatabase(fileURL: dbURL)
        } catch {
            fatalError("TNDatabase 打开 / migration 失败：\(error)")
        }
        let syncMetaDao: SyncMetaDao = SQLiteSyncMetaDao(database: database)
        let pendingMessageDao: PendingMessageDao = SQLitePendingMessageDao(database: database)
        let messageLocalDao: MessageLocalDao = SQLiteMessageLocalDao(database: database)
        let urlSession = URLSession(configuration: .default)
        let tokenAccessor = DefaultTokenAccessor(
            tokenStore: tokenStore,
            onSessionUpdated: { [weak session] response in
                guard let session else { return }
                await MainActor.run { session.signIn(response) }
            },
            onSessionCleared: { [weak session] in
                guard let session else { return }
                await MainActor.run { session.forceUnauthenticated() }
            }
        )
        let apiClient = APIClient(
            session: urlSession,
            serverConfigStore: serverConfigStore,
            tokenAccessor: tokenAccessor
        )
        let authRepository = AuthRepositoryImpl(apiClient: apiClient)
        let flashNoteRepository = FlashNoteRepositoryImpl(apiClient: apiClient)
        let messageRepository = MessageRepositoryImpl(
            apiClient: apiClient,
            messageLocalDao: messageLocalDao,
            usernameProvider: { [weak tokenStore] in tokenStore?.loadUsername() },
            currentUserIdProvider: { [weak tokenStore] in tokenStore?.loadUserId() }
        )
        let collectionRepository = CollectionRepositoryImpl(apiClient: apiClient)
        let contactRepository = ContactRepositoryImpl(apiClient: apiClient)
        let favoriteRepository = FavoriteRepositoryImpl(apiClient: apiClient)
        let favoriteRegistry = FavoriteIdRegistry()
        let mediaUrlResolver = MediaUrlResolver(serverConfigStore: serverConfigStore)
        let fileRepository = FileRepositoryImpl(
            session: urlSession,
            serverConfigStore: serverConfigStore,
            tokenAccessor: tokenAccessor,
            mediaUrlResolver: mediaUrlResolver
        )
        let flashNoteListViewModel = FlashNoteListViewModel(
            repository: flashNoteRepository,
            messageRepository: messageRepository
        )

        self.serverConfigStore = serverConfigStore
        self.tokenStore = tokenStore
        self.session = session
        self.apiClient = apiClient
        self.authRepository = authRepository
        self.flashNoteRepository = flashNoteRepository
        self.messageRepository = messageRepository
        self.collectionRepository = collectionRepository
        self.contactRepository = contactRepository
        self.favoriteRepository = favoriteRepository
        self.favoriteRegistry = favoriteRegistry
        self.fileRepository = fileRepository
        self.mediaUrlResolver = mediaUrlResolver
        
        let gestureLockStore = KeychainGestureLockStore()
        self.gestureLockStore = gestureLockStore

        self.authViewModel = AuthViewModel(authRepository: authRepository, session: session)
        self.flashNoteListViewModel = flashNoteListViewModel
        self.flashNoteSearchViewModel = FlashNoteSearchViewModel(repository: flashNoteRepository)
        let userRepository = UserRepositoryImpl(
            apiClient: apiClient,
            usernameProvider: { [weak tokenStore] in tokenStore?.loadUsername() }
        )
        self.userRepository = userRepository
        let profileViewModel = ProfileViewModel(repository: userRepository, fileRepository: fileRepository)
        self.profileViewModel = profileViewModel
        let profileStatsViewModel = ProfileStatsViewModel(
            flashNoteRepository: flashNoteRepository,
            favoriteRepository: favoriteRepository,
            messageRepository: messageRepository,
            usernameProvider: { [weak tokenStore] in tokenStore?.loadUsername() }
        )
        self.profileStatsViewModel = profileStatsViewModel
        let collectionsViewModel = CollectionsViewModel(
            collectionRepository: collectionRepository,
            flashNoteListViewModel: flashNoteListViewModel
        )
        self.collectionsViewModel = collectionsViewModel
        let favoritesViewModel = FavoritesViewModel(
            repository: favoriteRepository,
            registry: favoriteRegistry
        )
        self.favoritesViewModel = favoritesViewModel
        self.database = database
        self.syncMetaDao = syncMetaDao
        self.pendingMessageDao = pendingMessageDao
        self.messageLocalDao = messageLocalDao
        let syncRepository = SyncRepositoryImpl(
            apiClient: apiClient,
            syncMetaDao: syncMetaDao,
            usernameProvider: { [weak tokenStore] in tokenStore?.loadUsername() }
        )
        self.syncRepository = syncRepository
        // Step 2B：SyncEngine 接真实 sender。文本消息直接 `messageRepository.send`；
        // 媒体消息要求 PendingMessage.remoteUrl 已经被上传链路（ChatViewModel + FileRepository）填好。
        let syncEngine = SyncEngine(
            dao: pendingMessageDao,
            sender: MessageRepositoryPendingSender(messageRepository: messageRepository),
            usernameProvider: { [weak tokenStore] in tokenStore?.loadUsername() }
        )
        self.syncEngine = syncEngine
        // pull / bootstrap 成功后先应用 sync 快照到当前 UI 状态；messages 继续走本地表 + 会话广播。
        let flashNoteListViewModelRef = flashNoteListViewModel
        let syncCoordinator = SyncCoordinator(
            syncRepository: syncRepository,
            pendingMessageDao: pendingMessageDao,
            messageLocalDao: messageLocalDao,
            syncEngine: syncEngine,
            usernameProvider: { [weak tokenStore] in tokenStore?.loadUsername() },
            currentUserIdProvider: { [weak tokenStore] in tokenStore?.loadUserId() },
            onPullSucceeded: { [weak flashNoteListViewModelRef, weak profileViewModel, weak collectionsViewModel, weak favoritesViewModel, weak profileStatsViewModel] response in
                if let profile = response.profile {
                    await profileViewModel?.applySyncSnapshot(profile)
                }
                if !response.notes.isEmpty {
                    await flashNoteListViewModelRef?.applySyncSnapshot(response.notes)
                }
                if !response.collections.isEmpty {
                    await collectionsViewModel?.applySyncSnapshot(collections: response.collections)
                }
                if !response.favorites.isEmpty {
                    await favoritesViewModel?.applySyncSnapshot(response.favorites)
                }
                await profileStatsViewModel?.refresh()
            }
        )
        self.syncCoordinator = syncCoordinator
        // D2-I7-04 Step 2D-2：把 SyncCoordinator 的会话变更广播绑到 MessageRepository，
        // 让 `ChatViewModel.conversationChanged(for:)` 在 pull 落库后立即收到事件。
        messageRepository.bindConversationsChanged(syncCoordinator.conversationsChangedPublisher)
        // 队列变化时让 SyncCoordinator 主动刷新 pendingCount 给 UI。
        Task { [weak syncCoordinator, syncEngine] in
            await syncEngine.setOnQueueChanged { [weak syncCoordinator] in
                syncCoordinator?.refreshPendingCount()
            }
        }
        self.contactsViewModel = ContactsViewModel(repository: contactRepository)
        let shareStore = ShareInboxStore()
        self.shareInboxStore = shareStore
        self.shareInboxConsumer = ShareInboxConsumer(store: shareStore)
        self.attachmentSendingService = AttachmentSendingService(fileRepository: fileRepository)
        self.mediaPreloader = MessageMediaPreloader(fileRepository: fileRepository)
        self.scrollAnchorStore = ChatScrollAnchorStore()
        self.authenticatedImageLoader = AuthenticatedImageLoader(
            session: urlSession,
            tokenAccessor: tokenAccessor
        )
        self.draftStore = DraftStore()
        self.serverConfigObservable = ServerConfigStoreObservable(
            store: serverConfigStore,
            onSwitched: { [weak tokenStore, weak session] in
                tokenStore?.clear()
                if let session {
                    await MainActor.run { session.forceUnauthenticated() }
                }
            }
        )
    }

    /// 工厂：根据 list 弹出的「新建 / 编辑」请求构造对应 ViewModel。
    public func makeFlashNoteEditViewModel(_ mode: FlashNoteEditViewModel.Mode) -> FlashNoteEditViewModel {
        FlashNoteEditViewModel(mode: mode, repository: flashNoteRepository)
    }

    /// 工厂：构造一个 `ChatViewModel`。每次进入会话调用一次，离开后由 SwiftUI 释放。
    public func makeChatViewModel(
        key: ConversationKey,
        title: String,
        targetMessageId: Int64? = nil
    ) -> ChatViewModel {
        ChatViewModel(
            configuration: ChatViewModel.Configuration(
                key: key,
                title: title,
                targetMessageId: targetMessageId
            ),
            messageRepository: messageRepository,
            session: session,
            draftStore: draftStore,
            favoriteRepository: favoriteRepository,
            favoriteRegistry: favoriteRegistry,
            attachmentService: attachmentSendingService,
            mediaPreloader: mediaPreloader,
            scrollAnchorStore: scrollAnchorStore
        )
    }

    public func bootstrap() {
        CacheVersionMigrator.shared.migrateIfNeeded()
        if ProcessInfo.processInfo.arguments.contains("-tn.uitests.cleanState") {
            tokenStore.clear()
            serverConfigStore.useOfficial()
            try? shareInboxStore?.clearAll()
        }
        // D2-I6-12 注册登出全清：捕获弱引用，避免循环。
        session.setSignOutHandler { [weak self] in
            await self?.performSignOutCleanup()
        }
        // D2-I7-01 / I7-08：authenticated 时主动 bootstrap；登出时由 performSignOutCleanup 清。
        sessionStateCancellable = session.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                if case .authenticated = state {
                    self.syncCoordinator.bootstrapIfNeeded()
                    // D2-I7-06 登录/回前台时，如果有未发出的消息，尝试调起调度
                    SyncTaskManager.shared.scheduleBackgroundTasks()
                }
            }
        session.bootstrap()
        shareInboxConsumer.scan()
    }

    /// D2-I6-12 登出全清。与 Android `FlashNoteApp.signOutAndReset()` 主链对齐：
    /// - 清 Keychain（由 `AuthSession.signOut` 在调用本回调前已经完成）
    /// - 清 `UserRepository` in-memory + UserDefaults（多账号隔离 key）
    /// - 清 `ProfileStatsViewModel` 缓存
    /// - 清本地头像 `Caches/avatar.jpg`
    /// - 清 `ToastCenter` 当前展示
    /// - 清 `ShareInbox` 未消费条目
    /// - `Caches/tn.media/` 媒体缓存留给 `CacheVersionMigrator` 在下次冷启动重置（避免阻塞主线程）
    ///
    /// 注意：SwiftData / DebugLog / BGTask 取消在对应模块（D2-I6-13、D2-I7-06）落地后追加。
    @MainActor
    private func performSignOutCleanup() async {
        userRepository.clearCache()
        profileStatsViewModel.clearCache()
        AvatarLocalCache.clear()
        ToastCenter.shared.dismissCurrent()
        try? shareInboxStore?.clearAll()
        // D2-I7：sync 状态机回 idle、bootstrap Task 释放。
        syncCoordinator.resetForSignOut()
        // D2-I7-06/07 登出取消所有后台任务
        SyncTaskManager.shared.cancelAll()
        // D2-I6-12 清理当前会话 DebugLog
        DebugLog.shared.clearCurrentSession()
    }

    /// 处理 ShareInbox 里的一条 text 条目：落到对应会话（`ChatViewModel.sendText`）。
    /// 返回发送是否成功，由 UI 层决定消费确认后的后续交互。
    @MainActor
    public func submitShareEntryText(_ entry: ShareInboxEntry, key: ConversationKey) async -> Bool {
        guard entry.isText, let text = entry.text, !text.isEmpty else { return false }
        let vm = makeChatViewModel(
            key: key,
            title: key.isInbox ? "收集箱" : "",
            targetMessageId: nil
        )
        vm.inputText = text
        await vm.sendText()
        // 发送成功的判断：items 最后一条状态应为 .sent
        let ok = vm.items.last?.status == .sent
        if ok {
            // D2-I2-12 收集箱预览本地更新：往收集箱发文本成功后，立刻把列表
            // 收集箱行的预览刷成最新一条，不等远端 sync 回来。
            if key.isInbox {
                flashNoteListViewModel.updateInboxPreviewLocally(text)
            }
            shareInboxConsumer.markConsumed(entry)
        }
        return ok
    }

    // MARK: - D2-I2-13 / D2-I2-14 快速捕获

    /// 工厂：构造全屏快速捕获文本编辑器的 ViewModel。
    /// `submit` 闭包封装了「临时 ChatViewModel.sendText 写收集箱 + 成功后刷新预览」。
    public func makeQuickCaptureTextEditorViewModel() -> QuickCaptureTextEditorViewModel {
        QuickCaptureTextEditorViewModel { [weak self] text in
            guard let self else { return false }
            return await self.submitQuickCaptureText(text)
        }
    }

    /// D2-I2-14 快速捕获文本：写到收集箱（`flashNoteId = -1`），成功后刷新预览。
    @MainActor
    public func submitQuickCaptureText(_ rawText: String) async -> Bool {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let vm = makeChatViewModel(key: .flashNote(FlashNote.inboxId), title: "收集箱")
        vm.inputText = trimmed
        await vm.sendText()
        let ok = vm.items.last?.status == .sent
        if ok {
            flashNoteListViewModel.updateInboxPreviewLocally(trimmed)
        }
        return ok
    }

    /// D2-I2-13 快速捕获图片：写到收集箱，预览刷成「[图片]」。
    @MainActor
    public func submitQuickCaptureImage(localURL: URL) async -> Bool {
        await submitQuickCaptureMedia(.image, localURL: localURL, previewText: "[图片]")
    }

    /// D2-I2-13 快速捕获视频：写到收集箱，预览刷成「[视频]」。
    @MainActor
    public func submitQuickCaptureVideo(localURL: URL) async -> Bool {
        await submitQuickCaptureMedia(.video, localURL: localURL, previewText: "[视频]")
    }

    /// D2-I2-13 快速捕获文件：写到收集箱，预览带文件名。
    @MainActor
    public func submitQuickCaptureFile(localURL: URL) async -> Bool {
        let preview = "[文件] \(localURL.lastPathComponent)"
        return await submitQuickCaptureMedia(.file, localURL: localURL, previewText: preview)
    }

    private enum QuickCaptureMediaKind {
        case image, video, file
    }

    /// 媒体快速捕获统一通道：构造一次性 `ChatViewModel`，调对应 `sendXxx`，
    /// 成功后刷新收集箱预览。失败则把临时 ChatViewModel 的 `transientMessage`
    /// 转成 `FlashNoteListViewModel.transientMessage`，让列表 alert 起来。
    @MainActor
    private func submitQuickCaptureMedia(
        _ kind: QuickCaptureMediaKind,
        localURL: URL,
        previewText: String
    ) async -> Bool {
        let vm = makeChatViewModel(key: .flashNote(FlashNote.inboxId), title: "收集箱")
        switch kind {
        case .image: await vm.sendImage(localURL: localURL)
        case .video: await vm.sendVideo(localURL: localURL)
        case .file: await vm.sendFile(localURL: localURL)
        }
        let ok = vm.items.last?.status == .sent
        if ok {
            flashNoteListViewModel.updateInboxPreviewLocally(previewText)
        } else if let message = vm.transientMessage {
            flashNoteListViewModel.transientMessage = message
        }
        return ok
    }
}
