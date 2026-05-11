import Combine
import XCTest
@testable import ThunderNote

/// D2-I7-04 Step 2D-2 MessageRepositoryImpl 本地表 + publisher 单测。
final class MessageRepositoryLocalTests: XCTestCase {

    private var dbURL: URL!
    private var database: TNDatabase!
    private var dao: SQLiteMessageLocalDao!
    private var apiClient: APIClient!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tn-msgrepo-local-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("repo.sqlite3")
        database = try! TNDatabase(fileURL: dbURL)
        dao = SQLiteMessageLocalDao(database: database)
        // 本测试不调网络，APIClient 仅用于占位构造（reuse InMemoryTokenStore + DefaultTokenAccessor）。
        let tokenStore = InMemoryTokenStore()
        apiClient = APIClient(
            session: URLSession(configuration: .default),
            serverConfigStore: StaticServerConfig(baseURL: URL(string: "https://example.com")!),
            tokenAccessor: DefaultTokenAccessor(tokenStore: tokenStore)
        )
    }

    override func tearDown() {
        dao = nil
        database = nil
        apiClient = nil
        if let url = dbURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        super.tearDown()
    }

    // MARK: - listLocalMessages

    func test_listLocalMessages_returnsRowsForCurrentUsername() throws {
        try dao.upsert(Message(id: 1, content: "a", flashNoteId: 7, createdAt: "2026-05-11T00:00:00"), username: "alice", conversationKey: 7)
        try dao.upsert(Message(id: 2, content: "b", flashNoteId: 7, createdAt: "2026-05-11T00:01:00"), username: "alice", conversationKey: 7)
        try dao.upsert(Message(id: 3, content: "bob-only", flashNoteId: 7, createdAt: "2026-05-11T00:02:00"), username: "bob", conversationKey: 7)

        let repo = MessageRepositoryImpl(
            apiClient: apiClient,
            messageLocalDao: dao,
            usernameProvider: { "alice" },
            currentUserIdProvider: { 1 }
        )
        let rows = repo.listLocalMessages(key: .flashNote(7), limit: 10)
        XCTAssertEqual(rows.map { $0.content }, ["a", "b"])
    }

    func test_listLocalMessages_emptyWhenUsernameNilOrMissingDao() {
        let repoNoUsername = MessageRepositoryImpl(
            apiClient: apiClient,
            messageLocalDao: dao,
            usernameProvider: { nil },
            currentUserIdProvider: { 1 }
        )
        XCTAssertEqual(repoNoUsername.listLocalMessages(key: .flashNote(7), limit: 10).count, 0)

        let repoNoDao = MessageRepositoryImpl(
            apiClient: apiClient,
            messageLocalDao: nil,
            usernameProvider: { "alice" }
        )
        XCTAssertEqual(repoNoDao.listLocalMessages(key: .flashNote(7), limit: 10).count, 0)
    }

    // MARK: - upsertLocalMessage

    func test_upsertLocalMessage_writesToDao() throws {
        let repo = MessageRepositoryImpl(
            apiClient: apiClient,
            messageLocalDao: dao,
            usernameProvider: { "alice" },
            currentUserIdProvider: { 1 }
        )
        repo.upsertLocalMessage(Message(id: 11, content: "hi", flashNoteId: 7, createdAt: "2026-05-11T00:00:00"))
        let stored = try dao.listByConversation(username: "alice", conversationKey: 7, limit: 10)
        XCTAssertEqual(stored.first?.id, 11)
        XCTAssertEqual(stored.first?.content, "hi")
    }

    func test_upsertLocalMessage_skipsWhenResolverCannotComputeKey() throws {
        let repo = MessageRepositoryImpl(
            apiClient: apiClient,
            messageLocalDao: dao,
            usernameProvider: { "alice" },
            currentUserIdProvider: { 1 }
        )
        // 无 flashNoteId、无 sender/receiver 信息 → resolveForMessage 返回 nil
        repo.upsertLocalMessage(Message(id: 12, content: "x", flashNoteId: 0))
        XCTAssertEqual(try dao.countByConversation(username: "alice", conversationKey: 0), 0)
    }

    // MARK: - removeLocalMessages / clearLocalConversation

    func test_removeLocalMessages_deletesByIds() throws {
        try dao.upsert(Message(id: 1, flashNoteId: 7), username: "alice", conversationKey: 7)
        try dao.upsert(Message(id: 2, flashNoteId: 7), username: "alice", conversationKey: 7)
        try dao.upsert(Message(id: 3, flashNoteId: 7), username: "alice", conversationKey: 7)
        let repo = MessageRepositoryImpl(
            apiClient: apiClient,
            messageLocalDao: dao,
            usernameProvider: { "alice" }
        )
        repo.removeLocalMessages(ids: [1, 3])
        let remaining = try dao.listByConversation(username: "alice", conversationKey: 7, limit: 10)
        XCTAssertEqual(remaining.map { $0.id }, [2])
    }

    func test_clearLocalConversation_wipesByKey() throws {
        try dao.upsert(Message(id: 1, flashNoteId: -1), username: "alice", conversationKey: -1)
        try dao.upsert(Message(id: 2, flashNoteId: 7), username: "alice", conversationKey: 7)
        let repo = MessageRepositoryImpl(
            apiClient: apiClient,
            messageLocalDao: dao,
            usernameProvider: { "alice" }
        )
        repo.clearLocalConversation(key: .flashNote(-1))
        XCTAssertEqual(try dao.countByConversation(username: "alice", conversationKey: -1), 0)
        XCTAssertEqual(try dao.countByConversation(username: "alice", conversationKey: 7), 1)
    }

    // MARK: - conversationChanged publisher

    func test_conversationChanged_filtersByConversationKey() {
        let repo = MessageRepositoryImpl(
            apiClient: apiClient,
            messageLocalDao: dao,
            usernameProvider: { "alice" }
        )
        let upstream = PassthroughSubject<Set<Int64>, Never>()
        repo.bindConversationsChanged(upstream.eraseToAnyPublisher())

        var hitsFlash7 = 0
        var hitsPeer42 = 0
        var cancellables = Set<AnyCancellable>()
        repo.conversationChanged(for: .flashNote(7))
            .sink { hitsFlash7 += 1 }
            .store(in: &cancellables)
        repo.conversationChanged(for: .peer(42))
            .sink { hitsPeer42 += 1 }
            .store(in: &cancellables)

        upstream.send([7]) // 只命中 flash7
        upstream.send([ConversationKeyResolver.forContact(42)]) // 只命中 peer42
        upstream.send([7, ConversationKeyResolver.forContact(42)]) // 同时命中
        upstream.send([99]) // 都不命中

        XCTAssertEqual(hitsFlash7, 2)
        XCTAssertEqual(hitsPeer42, 2)
    }
}

