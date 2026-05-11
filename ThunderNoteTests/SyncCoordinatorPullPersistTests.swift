import Combine
import XCTest
@testable import ThunderNote

/// D2-I7-04 SyncCoordinator 把 pull 响应里的 messages 落到 messages_local + 广播 changedConversationKeys。
final class SyncCoordinatorPullPersistTests: XCTestCase {

    private var dbURL: URL!
    private var database: TNDatabase!
    private var dao: SQLiteMessageLocalDao!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tn-pullpersist-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("pull.sqlite3")
        database = try! TNDatabase(fileURL: dbURL)
        dao = SQLiteMessageLocalDao(database: database)
    }

    override func tearDown() {
        dao = nil
        database = nil
        if let url = dbURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        super.tearDown()
    }

    @MainActor
    func test_manualSync_persistsPulledMessages_andEmitsChangedKeys() async throws {
        let repo = StubSyncRepositoryPull()
        // 一条闪记消息（key=7）+ 一条联系人消息（receiverId=自己，sender=42 → key=forContact(42)）
        repo.pullResponse = SyncPullResponse(
            messages: [
                Message(id: 100, content: "hello-flash", flashNoteId: 7, createdAt: "2026-05-11T20:00:00"),
                Message(id: 101, senderId: 42, receiverId: 1, content: "hi-peer", flashNoteId: nil, createdAt: "2026-05-11T20:01:00"),
            ],
            serverTime: "S"
        )
        repo.pushResponse = SyncPushResponse(accepted: true)

        let coord = SyncCoordinator(
            syncRepository: repo,
            messageLocalDao: dao,
            usernameProvider: { "alice" },
            currentUserIdProvider: { 1 }
        )

        var receivedKeys: [Set<Int64>] = []
        var cancellables = Set<AnyCancellable>()
        coord.conversationsChangedPublisher
            .sink { receivedKeys.append($0) }
            .store(in: &cancellables)

        await coord.manualSync()

        // 落库
        let alice7 = try dao.listByConversation(username: "alice", conversationKey: 7, limit: 10)
        XCTAssertEqual(alice7.map { $0.content }, ["hello-flash"])
        let peerKey = ConversationKeyResolver.forContact(42)
        let alicePeer = try dao.listByConversation(username: "alice", conversationKey: peerKey, limit: 10)
        XCTAssertEqual(alicePeer.map { $0.content }, ["hi-peer"])

        // 广播 changedConversationKeys
        XCTAssertEqual(receivedKeys.count, 1)
        XCTAssertEqual(receivedKeys.first, Set([Int64(7), peerKey]))
    }

    @MainActor
    func test_manualSync_skipsMessagesWithoutId() async throws {
        let repo = StubSyncRepositoryPull()
        repo.pullResponse = SyncPullResponse(
            messages: [
                Message(id: nil, content: "no-id", flashNoteId: 7),
                Message(id: 5, content: "ok", flashNoteId: 7),
            ]
        )
        repo.pushResponse = SyncPushResponse(accepted: true)
        let coord = SyncCoordinator(
            syncRepository: repo,
            messageLocalDao: dao,
            usernameProvider: { "alice" },
            currentUserIdProvider: { 1 }
        )
        await coord.manualSync()
        XCTAssertEqual(try dao.countByConversation(username: "alice", conversationKey: 7), 1)
    }

    @MainActor
    func test_manualSync_emptyMessages_doesNotEmit() async throws {
        let repo = StubSyncRepositoryPull()
        repo.pullResponse = SyncPullResponse(messages: [])
        repo.pushResponse = SyncPushResponse(accepted: true)
        let coord = SyncCoordinator(
            syncRepository: repo,
            messageLocalDao: dao,
            usernameProvider: { "alice" },
            currentUserIdProvider: { 1 }
        )
        var hits = 0
        var cancellables = Set<AnyCancellable>()
        coord.conversationsChangedPublisher
            .sink { _ in hits += 1 }
            .store(in: &cancellables)
        await coord.manualSync()
        XCTAssertEqual(hits, 0)
    }

    @MainActor
    func test_resetForSignOut_deletesLocalMessagesForUser() async throws {
        try dao.upsert(Message(id: 1, content: "a", flashNoteId: 7), username: "alice", conversationKey: 7)
        try dao.upsert(Message(id: 1, content: "b", flashNoteId: 7), username: "bob", conversationKey: 7)
        let coord = SyncCoordinator(
            syncRepository: StubSyncRepositoryPull(),
            messageLocalDao: dao,
            usernameProvider: { "alice" }
        )
        coord.resetForSignOut()
        XCTAssertEqual(try dao.countByConversation(username: "alice", conversationKey: 7), 0)
        XCTAssertEqual(try dao.countByConversation(username: "bob", conversationKey: 7), 1)
    }
}

/// 文件局部 stub。
private final class StubSyncRepositoryPull: SyncRepository, @unchecked Sendable {
    var pullResponse: SyncPullResponse = SyncPullResponse()
    var pushResponse: SyncPushResponse = SyncPushResponse()
    func bootstrap() async throws -> SyncPullResponse { pullResponse }
    func pull() async throws -> SyncPullResponse { pullResponse }
    func push(_ payload: SyncPushRequest) async throws -> SyncPushResponse { pushResponse }
}
