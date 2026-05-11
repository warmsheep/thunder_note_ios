import Foundation
import SwiftUI

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

    public init() {
        let serverConfigStore = ServerConfigStore()
        let tokenStore = KeychainTokenStore()
        let session = AuthSession(tokenStore: tokenStore)
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
        let messageRepository = MessageRepositoryImpl(apiClient: apiClient)
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
        self.authViewModel = AuthViewModel(authRepository: authRepository, session: session)
        self.flashNoteListViewModel = flashNoteListViewModel
        self.flashNoteSearchViewModel = FlashNoteSearchViewModel(repository: flashNoteRepository)
        let userRepository = UserRepositoryImpl(
            apiClient: apiClient,
            usernameProvider: { [weak tokenStore] in tokenStore?.loadUsername() }
        )
        self.userRepository = userRepository
        self.profileViewModel = ProfileViewModel(repository: userRepository)
        self.collectionsViewModel = CollectionsViewModel(
            collectionRepository: collectionRepository,
            flashNoteListViewModel: flashNoteListViewModel
        )
        self.contactsViewModel = ContactsViewModel(repository: contactRepository)
        self.favoritesViewModel = FavoritesViewModel(
            repository: favoriteRepository,
            registry: favoriteRegistry
        )
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
        session.bootstrap()
        shareInboxConsumer.scan()
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
