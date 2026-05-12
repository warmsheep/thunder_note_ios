import XCTest
@testable import ThunderNote

final class ChatViewModelFavoriteTests: XCTestCase {
    @MainActor
    func test_toggleFavorite_updatesRegistryOptimistically() async {
        let repo = StubFavoriteRepoForChat()
        let registry = FavoriteIdRegistry()
        let session = makeSession()
        let vm = ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "x"),
            messageRepository: NoopMessageRepository(),
            session: session,
            draftStore: DraftStore(),
            favoriteRepository: repo,
            favoriteRegistry: registry
        )
        let item = ChatMessageItem(
            clientRequestId: nil,
            remoteId: 42, pendingLocalId: nil,
            status: .sent,
            message: Message(id: 42, content: "x")
        )

        await vm.toggleFavorite(item)

        XCTAssertTrue(registry.contains(42))
        XCTAssertEqual(repo.favoriteCount, 1)

        await vm.toggleFavorite(item)

        XCTAssertFalse(registry.contains(42))
        XCTAssertEqual(repo.unfavoriteCount, 1)
    }

    @MainActor
    func test_toggleFavorite_rollsBackOnFailure() async {
        let repo = StubFavoriteRepoForChat()
        repo.shouldFail = true
        let registry = FavoriteIdRegistry()
        let session = makeSession()
        let vm = ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "x"),
            messageRepository: NoopMessageRepository(),
            session: session,
            draftStore: DraftStore(),
            favoriteRepository: repo,
            favoriteRegistry: registry
        )
        let item = ChatMessageItem(
            clientRequestId: nil,
            remoteId: 42, pendingLocalId: nil,
            status: .sent,
            message: Message(id: 42)
        )

        await vm.toggleFavorite(item)

        XCTAssertFalse(registry.contains(42), "失败后应回滚")
        XCTAssertNotNil(vm.transientMessage)
    }

    @MainActor
    func test_toggleFavorite_blocksPendingMessage() async {
        let repo = StubFavoriteRepoForChat()
        let registry = FavoriteIdRegistry()
        let vm = ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "x"),
            messageRepository: NoopMessageRepository(),
            session: makeSession(),
            draftStore: DraftStore(),
            favoriteRepository: repo,
            favoriteRegistry: registry
        )
        let pending = ChatMessageItem(
            clientRequestId: "abc",
            remoteId: nil, pendingLocalId: nil,
            status: .pending,
            message: Message(content: "x", clientRequestId: "abc")
        )

        await vm.toggleFavorite(pending)

        XCTAssertEqual(repo.favoriteCount, 0)
        XCTAssertFalse(registry.contains(0))
        XCTAssertNotNil(vm.transientMessage)
    }

    @MainActor
    private func makeSession() -> AuthSession {
        let store = InMemoryTokenStore()
        let session = AuthSession(tokenStore: store)
        session.signIn(LoginResponse(
            accessToken: "A", refreshToken: "R", tokenType: "Bearer",
            expiresIn: 3600000,
            user: User(id: 1, username: "alice")
        ))
        return session
    }
}

private final class StubFavoriteRepoForChat: FavoriteRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.favstub.chat")
    var shouldFail: Bool = false
    private var _favoriteCount = 0
    private var _unfavoriteCount = 0

    var favoriteCount: Int { queue.sync { _favoriteCount } }
    var unfavoriteCount: Int { queue.sync { _unfavoriteCount } }

    func list() async throws -> [FavoriteItem] { [] }
    func favorite(messageId: Int64) async throws -> FavoriteItem {
        if shouldFail { throw APIError.business(code: 50000, message: "boom") }
        queue.sync { _favoriteCount += 1 }
        return FavoriteItem(id: 100, messageId: messageId)
    }
    func unfavorite(messageId: Int64) async throws {
        if shouldFail { throw APIError.business(code: 50000, message: "boom") }
        queue.sync { _unfavoriteCount += 1 }
    }
}

private final class NoopMessageRepository: MessageRepository, @unchecked Sendable {
    func listMessages(key: ConversationKey, page: Int, limit: Int) async throws -> PageData<Message> {
        PageData(records: [], total: 0, size: Int64(limit), current: 1, pages: 1)
    }
    func send(_ message: Message) async throws -> Message { message }
    func delete(id: Int64) async throws {}
    func deleteBatch(ids: [Int64]) async throws {}
    func clearInbox() async throws {}
    func merge(_ request: MessageMergeRequest) async throws -> Message {
        Message(id: 1, content: request.title, mediaType: "COMPOSITE")
    }
    func createComposite(_ request: CompositeMessageRequest) async throws -> Message {
        Message(id: 1, content: request.title, mediaType: "COMPOSITE")
    }
    func countMessages() async throws -> Int64 { 0 }
}
