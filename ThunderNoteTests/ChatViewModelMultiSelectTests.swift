import XCTest
@testable import ThunderNote

final class ChatViewModelMultiSelectTests: XCTestCase {

    @MainActor
    func test_enterMultiSelect_initiallySelectsTriggerItem() async {
        let m1 = Message(id: 1, content: "a", createdAt: "2026-05-11T10:00:00", mediaType: "TEXT")
        let m2 = Message(id: 2, content: "b", createdAt: "2026-05-11T10:01:00", mediaType: "TEXT")
        let repo = StubRepo(records: [m1, m2])
        let vm = makeVM(repo: repo)
        await vm.loadInitial()

        let trigger = ChatMessageItem(clientRequestId: nil, remoteId: 1, status: .sent, message: m1)
        vm.enterMultiSelect(initial: trigger)
        XCTAssertTrue(vm.isMultiSelectMode)
        XCTAssertEqual(vm.selectedRemoteIds, [1])
    }

    @MainActor
    func test_toggleSelection_addsAndRemoves() async {
        let m1 = Message(id: 1, content: "a", createdAt: "2026-05-11T10:00:00", mediaType: "TEXT")
        let m2 = Message(id: 2, content: "b", createdAt: "2026-05-11T10:01:00", mediaType: "TEXT")
        let repo = StubRepo(records: [m1, m2])
        let vm = makeVM(repo: repo)
        await vm.loadInitial()

        vm.enterMultiSelect()
        let i1 = ChatMessageItem(clientRequestId: nil, remoteId: 1, status: .sent, message: m1)
        let i2 = ChatMessageItem(clientRequestId: nil, remoteId: 2, status: .sent, message: m2)

        vm.toggleSelection(i1)
        vm.toggleSelection(i2)
        XCTAssertEqual(vm.selectedRemoteIds, [1, 2])
        vm.toggleSelection(i1)
        XCTAssertEqual(vm.selectedRemoteIds, [2])
    }

    @MainActor
    func test_exitMultiSelect_clearsState() async {
        let repo = StubRepo(records: [
            Message(id: 1, content: "a", createdAt: "2026-05-11T10:00:00", mediaType: "TEXT")
        ])
        let vm = makeVM(repo: repo)
        await vm.loadInitial()
        vm.enterMultiSelect(initial: ChatMessageItem(
            clientRequestId: nil, remoteId: 1, status: .sent,
            message: Message(id: 1, content: "a", mediaType: "TEXT")
        ))
        vm.exitMultiSelect()
        XCTAssertFalse(vm.isMultiSelectMode)
        XCTAssertTrue(vm.selectedRemoteIds.isEmpty)
    }

    @MainActor
    func test_deleteSelected_callsRepoBatchAndUpdatesItems() async {
        let m1 = Message(id: 1, content: "a", createdAt: "2026-05-11T10:00:00", mediaType: "TEXT")
        let m2 = Message(id: 2, content: "b", createdAt: "2026-05-11T10:01:00", mediaType: "TEXT")
        let repo = StubRepo(records: [m1, m2])
        let vm = makeVM(repo: repo)
        await vm.loadInitial()

        vm.enterMultiSelect()
        vm.toggleSelection(ChatMessageItem(clientRequestId: nil, remoteId: 1, status: .sent, message: m1))
        await vm.deleteSelected()

        XCTAssertEqual(repo.deleteBatchCalls, [[1]])
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.remoteId, 2)
        XCTAssertFalse(vm.isMultiSelectMode)
    }

    @MainActor
    func test_mergeSelected_callsMergeAndAppendsCardItem() async {
        let m1 = Message(id: 1, content: "a", createdAt: "2026-05-11T10:00:00", mediaType: "TEXT")
        let m2 = Message(id: 2, content: "b", createdAt: "2026-05-11T10:01:00", mediaType: "TEXT")
        let repo = StubRepo(
            records: [m1, m2],
            mergeResult: Message(
                id: 99,
                senderId: 1,
                content: "卡片",
                flashNoteId: 2,
                createdAt: "2026-05-11T10:02:00",
                mediaType: "COMPOSITE",
                payload: CardPayload(cardType: "MESSAGE_COLLECTION", title: "卡片")
            )
        )
        let vm = makeVM(repo: repo)
        await vm.loadInitial()

        vm.enterMultiSelect()
        vm.toggleSelection(ChatMessageItem(clientRequestId: nil, remoteId: 1, status: .sent, message: m1))
        vm.toggleSelection(ChatMessageItem(clientRequestId: nil, remoteId: 2, status: .sent, message: m2))
        await vm.mergeSelected(title: "卡片")

        XCTAssertEqual(repo.mergeCalls.count, 1)
        XCTAssertEqual(repo.mergeCalls.first?.messageIds, [1, 2])
        XCTAssertEqual(repo.mergeCalls.first?.title, "卡片")
        XCTAssertEqual(vm.items.last?.remoteId, 99)
        XCTAssertFalse(vm.isMultiSelectMode)
    }

    @MainActor
    func test_mergeSelected_emptyTitleProducesTransientMessage() async {
        let repo = StubRepo(records: [
            Message(id: 1, content: "a", createdAt: "2026-05-11T10:00:00", mediaType: "TEXT")
        ])
        let vm = makeVM(repo: repo)
        await vm.loadInitial()

        vm.enterMultiSelect()
        vm.toggleSelection(ChatMessageItem(
            clientRequestId: nil, remoteId: 1, status: .sent,
            message: Message(id: 1, content: "a", mediaType: "TEXT")
        ))
        await vm.mergeSelected(title: "  ")
        XCTAssertEqual(vm.transientMessage, "请输入卡片标题")
    }

    @MainActor
    func test_loadMoreOlder_publishesPrependAnchor() async {
        let m1 = Message(id: 1, content: "a", createdAt: "2026-05-11T10:00:00", mediaType: "TEXT")
        let m2 = Message(id: 2, content: "b", createdAt: "2026-05-11T10:01:00", mediaType: "TEXT")
        let m0 = Message(id: 0, content: "older", createdAt: "2026-05-11T09:00:00", mediaType: "TEXT")
        // 第一页返回 m1 / m2；第二页返回 m0（更早）
        let repo = StubRepo(pages: [
            PageData(records: [m1, m2], total: 3, size: 2, current: 1, pages: 2),
            PageData(records: [m0], total: 3, size: 2, current: 2, pages: 2)
        ])
        let vm = makeVM(repo: repo)
        await vm.loadInitial()
        XCTAssertEqual(vm.items.first?.remoteId, 1)

        await vm.loadMoreOlder()
        // anchor 应等于 prepend 前的第一条 remoteId（旧的 m1 = 1）
        XCTAssertEqual(vm.prependAnchorMessageId, 1)
        // m0 排在最前
        XCTAssertEqual(vm.items.first?.remoteId, 0)

        vm.didConsumePrependAnchor()
        XCTAssertNil(vm.prependAnchorMessageId)
    }

    @MainActor
    func test_onDisappear_writesAnchorToStore() async {
        let m1 = Message(id: 1, content: "a", createdAt: "2026-05-11T10:00:00", mediaType: "TEXT")
        let m2 = Message(id: 2, content: "b", createdAt: "2026-05-11T10:01:00", mediaType: "TEXT")
        let repo = StubRepo(records: [m1, m2])
        let defaults = UserDefaults(suiteName: "tn.tests.scrollAnchor.vm")!
        defaults.removePersistentDomain(forName: "tn.tests.scrollAnchor.vm")
        let store = ChatScrollAnchorStore(defaults: defaults)
        let vm = makeVM(repo: repo, scrollAnchorStore: store)
        await vm.loadInitial()
        vm.onDisappear()
        XCTAssertEqual(store.anchor(for: .flashNote(2)), 2)
    }

    @MainActor
    func test_onAppear_restoresAnchorWhenHit() async {
        let m1 = Message(id: 1, content: "a", createdAt: "2026-05-11T10:00:00", mediaType: "TEXT")
        let m2 = Message(id: 2, content: "b", createdAt: "2026-05-11T10:01:00", mediaType: "TEXT")
        let repo = StubRepo(records: [m1, m2])
        let defaults = UserDefaults(suiteName: "tn.tests.scrollAnchor.vm2")!
        defaults.removePersistentDomain(forName: "tn.tests.scrollAnchor.vm2")
        let store = ChatScrollAnchorStore(defaults: defaults)
        store.setAnchor(1, for: .flashNote(2))

        let vm = makeVM(repo: repo, scrollAnchorStore: store)
        await vm.onAppear()
        XCTAssertEqual(vm.scrollTargetMessageId, 1)
    }

    // MARK: - Helpers

    @MainActor
    private func makeVM(
        repo: MessageRepository,
        scrollAnchorStore: ChatScrollAnchorStore? = nil
    ) -> ChatViewModel {
        let store = InMemoryTokenStore()
        let session = AuthSession(tokenStore: store)
        session.signIn(LoginResponse(
            accessToken: "A", refreshToken: "R", tokenType: "Bearer",
            expiresIn: 3600000,
            user: User(id: 1, username: "alice")
        ))
        return ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "测试"),
            messageRepository: repo,
            session: session,
            draftStore: DraftStore(),
            scrollAnchorStore: scrollAnchorStore
        )
    }
}

private final class StubRepo: MessageRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.merge.stub")
    private var _records: [Message]
    private var _pages: [PageData<Message>]
    private var _pageIndex: Int = 0
    private let mergeResult: Message?
    private(set) var mergeCalls: [MessageMergeRequest] = []
    private(set) var deleteBatchCalls: [[Int64]] = []

    init(records: [Message] = [], mergeResult: Message? = nil) {
        self._records = records
        self._pages = []
        self.mergeResult = mergeResult
    }

    init(pages: [PageData<Message>], mergeResult: Message? = nil) {
        self._records = []
        self._pages = pages
        self.mergeResult = mergeResult
    }

    func listMessages(key: ConversationKey, page: Int, limit: Int) async throws -> PageData<Message> {
        if _pages.isEmpty {
            let snap = queue.sync { _records }
            return PageData(records: snap, total: Int64(snap.count), size: Int64(limit), current: 1, pages: 1)
        }
        let idx = max(0, min(page - 1, _pages.count - 1))
        return _pages[idx]
    }

    func send(_ message: Message) async throws -> Message { message }
    func delete(id: Int64) async throws {}
    func deleteBatch(ids: [Int64]) async throws {
        queue.sync { deleteBatchCalls.append(ids) }
    }
    func clearInbox() async throws {}
    func merge(_ request: MessageMergeRequest) async throws -> Message {
        queue.sync { mergeCalls.append(request) }
        return mergeResult ?? Message(id: 100, content: request.title, mediaType: "COMPOSITE")
    }
    func createComposite(_ request: CompositeMessageRequest) async throws -> Message {
        Message(id: 200, content: request.title, mediaType: "COMPOSITE")
    }
}
