import XCTest
@testable import ThunderNote

final class ChatViewModelTests: XCTestCase {
    @MainActor
    func test_loadInitial_populatesItemsSorted() async {
        let repo = StubMessageRepository(messages: [
            Message(id: 2, senderId: 1, receiverId: 1, content: "hi 2", createdAt: "2026-05-11T10:01:00", mediaType: "TEXT"),
            Message(id: 1, senderId: 1, receiverId: 1, content: "hi 1", createdAt: "2026-05-11T10:00:00", mediaType: "TEXT")
        ])
        let session = makeSession()
        let vm = ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "工作"),
            messageRepository: repo,
            session: session,
            draftStore: DraftStore()
        )
        await vm.loadInitial()
        XCTAssertEqual(vm.items.count, 2)
        XCTAssertEqual(vm.items.first?.message.id, 1, "应按 createdAt 升序排列")
        XCTAssertEqual(vm.items.last?.message.id, 2)
    }

    @MainActor
    func test_sendText_optimisticInsertThenReplaceOnSuccess() async {
        let repo = StubMessageRepository(
            messages: [],
            sendResult: { msg in
                Message(
                    id: 100,
                    senderId: msg.senderId,
                    receiverId: msg.receiverId,
                    content: msg.content,
                    flashNoteId: msg.flashNoteId,
                    clientRequestId: msg.clientRequestId,
                    createdAt: "2026-05-11T11:00:00",
                    mediaType: "TEXT"
                )
            }
        )
        let session = makeSession()
        let vm = ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "工作"),
            messageRepository: repo,
            session: session,
            draftStore: DraftStore()
        )
        await vm.loadInitial()
        vm.inputText = "你好"
        await vm.sendText()
        XCTAssertEqual(vm.items.count, 1)
        let item = vm.items[0]
        XCTAssertEqual(item.remoteId, 100)
        XCTAssertEqual(item.status, .sent)
        XCTAssertEqual(vm.inputText, "", "发送成功后清空输入")
    }

    @MainActor
    func test_sendText_failureKeepsItemAsFailed() async {
        let repo = StubMessageRepository(messages: [], sendError: APIError.business(code: 50000, message: "服务器错误"))
        let session = makeSession()
        let vm = ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "工作"),
            messageRepository: repo,
            session: session,
            draftStore: DraftStore()
        )
        await vm.loadInitial()
        vm.inputText = "你好"
        await vm.sendText()
        XCTAssertEqual(vm.items.count, 1)
        if case .failed(let reason) = vm.items[0].status {
            XCTAssertEqual(reason, "服务器错误")
        } else {
            XCTFail("应进入 failed 状态")
        }
    }

    @MainActor
    func test_sendText_blocksWhenInputBlank() async {
        let repo = StubMessageRepository(messages: [])
        let session = makeSession()
        let vm = ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "工作"),
            messageRepository: repo,
            session: session,
            draftStore: DraftStore()
        )
        vm.inputText = "   \n  "
        await vm.sendText()
        XCTAssertEqual(vm.items.count, 0)
        XCTAssertEqual(repo.sendCallCount, 0)
    }

    @MainActor
    func test_draft_persistsAcrossViewModelInstances() async {
        let store = DraftStore()
        let repo = StubMessageRepository(messages: [])
        let session = makeSession()
        let key = ConversationKey.flashNote(7)

        let vm1 = ChatViewModel(
            configuration: .init(key: key, title: "x"),
            messageRepository: repo,
            session: session,
            draftStore: store
        )
        vm1.inputText = "未发送的草稿"
        vm1.onDisappear()

        let vm2 = ChatViewModel(
            configuration: .init(key: key, title: "x"),
            messageRepository: repo,
            session: session,
            draftStore: store
        )
        XCTAssertEqual(vm2.inputText, "未发送的草稿")
    }

    @MainActor
    func test_delete_remoteMessageRemovesItem() async {
        let repo = StubMessageRepository(messages: [
            Message(id: 1, senderId: 1, receiverId: 1, content: "x", createdAt: "2026-05-11T10:00:00", mediaType: "TEXT")
        ])
        let vm = ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "x"),
            messageRepository: repo,
            session: makeSession(),
            draftStore: DraftStore()
        )
        await vm.loadInitial()
        XCTAssertEqual(vm.items.count, 1)
        await vm.delete(vm.items[0])
        XCTAssertEqual(vm.items.count, 0)
        XCTAssertEqual(repo.deleteIds, [1])
    }

    @MainActor
    func test_delete_pendingMessageRemovedLocallyOnly() async {
        let repo = StubMessageRepository(messages: [], sendError: APIError.business(code: 50000, message: "失败"))
        let vm = ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "x"),
            messageRepository: repo,
            session: makeSession(),
            draftStore: DraftStore()
        )
        await vm.loadInitial()
        vm.inputText = "失败的消息"
        await vm.sendText()
        XCTAssertEqual(vm.items.count, 1)
        await vm.delete(vm.items[0])
        XCTAssertEqual(vm.items.count, 0)
        XCTAssertEqual(repo.deleteIds, [], "本地 pending 消息不应触发后端删除")
    }

    @MainActor
    private func makeSession() -> AuthSession {
        let store = InMemoryTokenStore()
        let session = AuthSession(tokenStore: store)
        let response = LoginResponse(
            accessToken: "A",
            refreshToken: "R",
            tokenType: "Bearer",
            expiresIn: 3600000,
            user: User(id: 1, username: "alice")
        )
        session.signIn(response)
        return session
    }
}

private final class StubMessageRepository: MessageRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.message.stub")
    private var _messages: [Message]
    private var _sendCallCount: Int = 0
    private var _deleteIds: [Int64] = []
    private let sendResult: (@Sendable (Message) -> Message)?
    private let sendError: APIError?

    init(
        messages: [Message],
        sendResult: (@Sendable (Message) -> Message)? = nil,
        sendError: APIError? = nil
    ) {
        self._messages = messages
        self.sendResult = sendResult
        self.sendError = sendError
    }

    var sendCallCount: Int { queue.sync { _sendCallCount } }
    var deleteIds: [Int64] { queue.sync { _deleteIds } }

    func listMessages(key: ConversationKey, page: Int, limit: Int) async throws -> PageData<Message> {
        let snapshot = queue.sync { _messages }
        return PageData(records: snapshot, total: Int64(snapshot.count), size: Int64(limit), current: 1, pages: 1)
    }

    func send(_ message: Message) async throws -> Message {
        queue.sync { _sendCallCount += 1 }
        if let sendError { throw sendError }
        if let sendResult { return sendResult(message) }
        return message
    }

    func delete(id: Int64) async throws {
        queue.sync { _deleteIds.append(id) }
    }

    func deleteBatch(ids: [Int64]) async throws {
        queue.sync { _deleteIds.append(contentsOf: ids) }
    }

    func clearInbox() async throws {}

    func merge(_ request: MessageMergeRequest) async throws -> Message {
        Message(id: 1, content: request.title, mediaType: "COMPOSITE")
    }

    func createComposite(_ request: CompositeMessageRequest) async throws -> Message {
        Message(id: 1, content: request.title, mediaType: "COMPOSITE")
    }
    func countMessages() async throws -> Int64 { 0 }
}
