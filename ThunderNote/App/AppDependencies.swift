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
    public let messageRepository: MessageRepository
    public let draftStore: DraftStore
    public let collectionRepository: CollectionRepository
    public let contactRepository: ContactRepository
    public let collectionsViewModel: CollectionsViewModel
    public let contactsViewModel: ContactsViewModel

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
        let flashNoteListViewModel = FlashNoteListViewModel(repository: flashNoteRepository)

        self.serverConfigStore = serverConfigStore
        self.tokenStore = tokenStore
        self.session = session
        self.apiClient = apiClient
        self.authRepository = authRepository
        self.flashNoteRepository = flashNoteRepository
        self.messageRepository = messageRepository
        self.collectionRepository = collectionRepository
        self.contactRepository = contactRepository
        self.authViewModel = AuthViewModel(authRepository: authRepository, session: session)
        self.flashNoteListViewModel = flashNoteListViewModel
        self.collectionsViewModel = CollectionsViewModel(
            collectionRepository: collectionRepository,
            flashNoteListViewModel: flashNoteListViewModel
        )
        self.contactsViewModel = ContactsViewModel(repository: contactRepository)
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
    public func makeChatViewModel(key: ConversationKey, title: String) -> ChatViewModel {
        ChatViewModel(
            configuration: ChatViewModel.Configuration(key: key, title: title),
            messageRepository: messageRepository,
            session: session,
            draftStore: draftStore
        )
    }

    public func bootstrap() {
        CacheVersionMigrator.shared.migrateIfNeeded()
        if ProcessInfo.processInfo.arguments.contains("-tn.uitests.cleanState") {
            tokenStore.clear()
            serverConfigStore.useOfficial()
        }
        session.bootstrap()
    }
}
