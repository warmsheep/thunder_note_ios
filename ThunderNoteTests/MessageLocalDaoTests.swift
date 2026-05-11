import XCTest
@testable import ThunderNote

/// D2-I7-04 MessageLocalDao 单测。
final class MessageLocalDaoTests: XCTestCase {

    private var dbURL: URL!
    private var database: TNDatabase!
    private var dao: SQLiteMessageLocalDao!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tn-msglocal-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("msg.sqlite3")
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

    // MARK: - upsert / list

    func test_upsert_thenList_returnsRoundTripValues() throws {
        let m = Message(
            id: 100,
            senderId: 1,
            receiverId: 2,
            content: "hello",
            readStatus: false,
            flashNoteId: 7,
            clientRequestId: "req-1",
            role: "USER",
            createdAt: "2026-05-11T22:00:00",
            mediaType: "TEXT",
            mediaUrl: nil,
            mediaDuration: nil,
            thumbnailUrl: nil,
            fileName: nil,
            fileSize: nil,
            payload: nil
        )
        try dao.upsert(m, username: "alice", conversationKey: 7)
        let list = try dao.listByConversation(username: "alice", conversationKey: 7, limit: 10)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].id, 100)
        XCTAssertEqual(list[0].content, "hello")
        XCTAssertEqual(list[0].clientRequestId, "req-1")
        XCTAssertEqual(list[0].readStatus, false)
        XCTAssertEqual(list[0].mediaType, "TEXT")
    }

    func test_upsertAll_orderedByCreatedAtAsc() throws {
        let pairs: [(Message, Int64)] = [
            (Message(id: 3, content: "c", createdAt: "2026-05-11T03:00:00"), 7),
            (Message(id: 1, content: "a", createdAt: "2026-05-11T01:00:00"), 7),
            (Message(id: 2, content: "b", createdAt: "2026-05-11T02:00:00"), 7),
        ]
        try dao.upsertAll(pairs, username: "alice")
        let list = try dao.listByConversation(username: "alice", conversationKey: 7, limit: 10)
        XCTAssertEqual(list.map { $0.content }, ["a", "b", "c"])
    }

    func test_upsertAll_filtersByUsername() throws {
        try dao.upsertAll([(Message(id: 1, content: "alice"), Int64(7))], username: "alice")
        try dao.upsertAll([(Message(id: 1, content: "bob"), Int64(7))], username: "bob")
        XCTAssertEqual(try dao.listByConversation(username: "alice", conversationKey: 7, limit: 10).first?.content, "alice")
        XCTAssertEqual(try dao.listByConversation(username: "bob", conversationKey: 7, limit: 10).first?.content, "bob")
    }

    func test_upsert_replacesByPrimaryKey() throws {
        try dao.upsert(Message(id: 1, content: "v1", createdAt: "2026-01-01T00:00:00"), username: "alice", conversationKey: 7)
        try dao.upsert(Message(id: 1, content: "v2", createdAt: "2026-01-01T00:00:00"), username: "alice", conversationKey: 7)
        let list = try dao.listByConversation(username: "alice", conversationKey: 7, limit: 10)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.content, "v2")
    }

    func test_upsert_skipsMessageWithoutId() throws {
        try dao.upsert(Message(id: nil, content: "no-id"), username: "alice", conversationKey: 7)
        XCTAssertEqual(try dao.countByConversation(username: "alice", conversationKey: 7), 0)
    }

    // MARK: - findByClientRequestId / count / delete

    func test_findByClientRequestId_returnsLatest() throws {
        try dao.upsert(Message(id: 1, clientRequestId: "req-x"), username: "alice", conversationKey: 7)
        let found = try dao.findByClientRequestId(username: "alice", clientRequestId: "req-x")
        XCTAssertEqual(found?.id, 1)
    }

    func test_deleteByConversation_clearsOnlyTargetConversation() throws {
        try dao.upsert(Message(id: 1, content: "a"), username: "alice", conversationKey: 7)
        try dao.upsert(Message(id: 2, content: "b"), username: "alice", conversationKey: 9)
        try dao.deleteByConversation(username: "alice", conversationKey: 7)
        XCTAssertEqual(try dao.countByConversation(username: "alice", conversationKey: 7), 0)
        XCTAssertEqual(try dao.countByConversation(username: "alice", conversationKey: 9), 1)
    }

    func test_deleteAllForUsername_doesNotAffectOtherUsers() throws {
        try dao.upsert(Message(id: 1, content: "a"), username: "alice", conversationKey: 7)
        try dao.upsert(Message(id: 1, content: "b"), username: "bob", conversationKey: 7)
        try dao.deleteAllForUsername("alice")
        XCTAssertEqual(try dao.countByConversation(username: "alice", conversationKey: 7), 0)
        XCTAssertEqual(try dao.countByConversation(username: "bob", conversationKey: 7), 1)
    }
}
