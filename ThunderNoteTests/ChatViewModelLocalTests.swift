import Combine
import XCTest
@testable import ThunderNote

/// D2-I7-04 Step 2D-2 ChatViewModel 离线优先 + 本地表订阅单测。
final class ChatViewModelLocalTests: XCTestCase {

    @MainActor
    func test_loadInitial_paintsLocalSnapshotBeforeNetwork() async {
        let local = [
            Message(id: 10, content: "local-a", createdAt: "2026-05-11T09:00:00"),
            Message(id: 11, content: "local-b", createdAt: "2026-05-11T09:01:00"),
        ]
        let network = [
            Message(id: 10, content: "local-a", createdAt: "2026-05-11T09:00:00"),
            Message(id: 12, content: "new-c", createdAt: "2026-05-11T09:02:00"),
        ]
        let repo = LocalAwareMessageRepository(local: local, network: network)
        let vm = makeViewModel(repo: repo)
        await vm.loadInitial()
        // 网络成功覆盖：local 中已被网络刷新的部分被替换，新增 new-c 加入。
        XCTAssertEqual(vm.items.map { $0.message.content }, ["local-a", "new-c"])
        XCTAssertEqual(vm.loadState, .loaded)
    }

    @MainActor
    func test_loadInitial_keepsLocalAndToastsWhenNetworkFails() async {
        let local = [Message(id: 10, content: "local-only", createdAt: "2026-05-11T09:00:00")]
        let repo = LocalAwareMessageRepository(
            local: local,
            networkError: .business(code: 50001, message: "服务不可用")
        )
        let vm = makeViewModel(repo: repo)
        await vm.loadInitial()
        // 不进 error 态：仍展示本地内容
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertEqual(vm.transientMessage, "服务不可用")
    }

    @MainActor
    func test_loadInitial_fallsBackToErrorWhenNoLocalAndNetworkFails() async {
        let repo = LocalAwareMessageRepository(
            local: [],
            networkError: .business(code: 50001, message: "boom")
        )
        let vm = makeViewModel(repo: repo)
        await vm.loadInitial()
        XCTAssertEqual(vm.items.count, 0)
        if case .error(let msg) = vm.loadState {
            XCTAssertEqual(msg, "boom")
        } else {
            XCTFail("expected error state, got \(vm.loadState)")
        }
    }

    @MainActor
    func test_conversationChangedEvent_mergesLatestLocalRows() async {
        let initialLocal = [Message(id: 10, content: "a", createdAt: "2026-05-11T09:00:00")]
        let updatedLocal = initialLocal + [Message(id: 11, content: "b-from-pull", createdAt: "2026-05-11T09:05:00")]
        let repo = LocalAwareMessageRepository(local: initialLocal, network: initialLocal)
        let vm = makeViewModel(repo: repo)
        await vm.onAppear()
        XCTAssertEqual(vm.items.map { $0.message.content }, ["a"])

        // 模拟 SyncCoordinator 在 pull 落库后推一轮：先更新 local snapshot，再 emit。
        repo.setLocal(updatedLocal)
        repo.emitConversationChanged()
        try? await Task.sleep(nanoseconds: 60_000_000) // 给 DispatchQueue.main 一次回调
        XCTAssertEqual(vm.items.map { $0.message.content }, ["a", "b-from-pull"])
    }

    @MainActor
    func test_sendText_upsertsConfirmedMessageToLocal() async {
        let repo = LocalAwareMessageRepository(local: [], network: [])
        let vm = makeViewModel(repo: repo)
        await vm.onAppear()
        vm.inputText = "hi"
        await vm.sendText()
        XCTAssertEqual(repo.upsertedIds, [99])
    }

    @MainActor
    func test_delete_removesFromLocalToo() async {
        let local = [Message(id: 10, content: "x", createdAt: "2026-05-11T09:00:00")]
        let repo = LocalAwareMessageRepository(local: local, network: local)
        let vm = makeViewModel(repo: repo)
        await vm.onAppear()
        await vm.delete(vm.items[0])
        XCTAssertEqual(repo.removedIds, [10])
    }

    // MARK: - helpers

    @MainActor
    private func makeViewModel(repo: MessageRepository) -> ChatViewModel {
        let tokenStore = InMemoryTokenStore()
        let session = AuthSession(tokenStore: tokenStore)
        session.signIn(LoginResponse(
            accessToken: "A", refreshToken: "R", tokenType: "Bearer",
            expiresIn: 3600000, user: User(id: 1, username: "alice")
        ))
        return ChatViewModel(
            configuration: .init(key: .flashNote(7), title: "x"),
            messageRepository: repo,
            session: session,
            draftStore: DraftStore()
        )
    }
}

/// 本地表 + publisher 感知的 stub。
private final class LocalAwareMessageRepository: MessageRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.chat.local")
    private var _local: [Message]
    private var _network: [Message]
    private let networkError: APIError?
    private let conversationChangedSubject = PassthroughSubject<Void, Never>()
    private var _upsertedIds: [Int64] = []
    private var _removedIds: [Int64] = []

    init(local: [Message], network: [Message] = [], networkError: APIError? = nil) {
        _local = local
        _network = network
        self.networkError = networkError
    }

    func setLocal(_ items: [Message]) {
        queue.sync { _local = items }
    }

    func emitConversationChanged() {
        conversationChangedSubject.send(())
    }

    var upsertedIds: [Int64] { queue.sync { _upsertedIds } }
    var removedIds: [Int64] { queue.sync { _removedIds } }

    // MARK: - MessageRepository

    func listMessages(key: ConversationKey, page: Int, limit: Int) async throws -> PageData<Message> {
        if let err = networkError { throw err }
        let snapshot = queue.sync { _network }
        let json = #"{"records":[],"total":0,"size":\#(limit),"current":\#(page),"pages":1}"#
        // 用 JSON decode 出空骨架再人工塞入 records（PageData 没暴露 init）。
        var page = try! JSONDecoder().decode(PageData<Message>.self, from: Data(json.utf8))
        // Hack: 通过 KeyedDecodingContainer 重新 encode/decode
        let encoded = try! JSONEncoder().encode(PageBox(records: snapshot, current: page.safeCurrent, pages: page.safePages, size: page.size ?? Int64(limit), total: Int64(snapshot.count)))
        page = try! JSONDecoder().decode(PageData<Message>.self, from: encoded)
        return page
    }

    private struct PageBox: Encodable {
        let records: [Message]
        let current: Int64
        let pages: Int64
        let size: Int64
        let total: Int64
    }

    func send(_ message: Message) async throws -> Message {
        // 返回带 id 的"已确认"版本
        var confirmed = message
        confirmed.id = 99
        return confirmed
    }

    func delete(id: Int64) async throws {}
    func deleteBatch(ids: [Int64]) async throws {}
    func clearInbox() async throws {}
    func merge(_ request: MessageMergeRequest) async throws -> Message { Message(id: 1) }
    func createComposite(_ request: CompositeMessageRequest) async throws -> Message { Message(id: 1) }
    func countMessages() async throws -> Int64 { 0 }

    func listLocalMessages(key: ConversationKey, limit: Int) -> [Message] {
        queue.sync { _local }
    }

    func upsertLocalMessage(_ message: Message) {
        guard let id = message.id else { return }
        queue.sync { _upsertedIds.append(id) }
    }

    func removeLocalMessages(ids: [Int64]) {
        queue.sync { _removedIds.append(contentsOf: ids) }
    }

    func clearLocalConversation(key: ConversationKey) {
        queue.sync { _local.removeAll() }
    }

    func conversationChanged(for key: ConversationKey) -> AnyPublisher<Void, Never> {
        conversationChangedSubject.eraseToAnyPublisher()
    }
}
