import XCTest
@testable import ThunderNote

/// D2-I7-05 PendingMessage DAO 单测。
final class PendingMessageDaoTests: XCTestCase {

    private var dbURL: URL!
    private var database: TNDatabase!
    private var dao: SQLitePendingMessageDao!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tn-pending-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("pending.sqlite3")
        database = try! TNDatabase(fileURL: dbURL)
        dao = SQLitePendingMessageDao(database: database)
    }

    override func tearDown() {
        dao = nil
        database = nil
        if let url = dbURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        super.tearDown()
    }

    // MARK: - insert / find / list

    func test_insertAssignsLocalId_andRoundTrips() throws {
        let id = try dao.insert(.alice(content: "hello"))
        XCTAssertGreaterThan(id, 0)
        let loaded = try dao.findByLocalId(id)
        XCTAssertEqual(loaded?.content, "hello")
        XCTAssertEqual(loaded?.status, .queued)
        XCTAssertEqual(loaded?.username, "alice")
    }

    func test_listAll_returnsOrderedByCreatedAtAsc_perUser() throws {
        _ = try dao.insert(.alice(content: "a", createdAt: 100))
        _ = try dao.insert(.alice(content: "c", createdAt: 300))
        _ = try dao.insert(.alice(content: "b", createdAt: 200))
        _ = try dao.insert(.bob(content: "bob-x", createdAt: 150))
        let alice = try dao.listAll(username: "alice")
        XCTAssertEqual(alice.map { $0.content }, ["a", "b", "c"])
        let bob = try dao.listAll(username: "bob")
        XCTAssertEqual(bob.map { $0.content }, ["bob-x"])
    }

    // MARK: - pickNextDispatchable

    func test_pickNextDispatchable_prefersQueuedOverFailed_byCreatedAt() throws {
        // FAILED 较早，QUEUED 较晚 → 仍优先 QUEUED。
        var failed = PendingMessageLocal.alice(content: "old-failed", createdAt: 100)
        failed.status = .failed
        _ = try dao.insert(failed)
        _ = try dao.insert(.alice(content: "queued-newer", createdAt: 200))
        let next = try dao.pickNextDispatchable(username: "alice")
        XCTAssertEqual(next?.status, .queued)
        XCTAssertEqual(next?.content, "queued-newer")
    }

    func test_pickNextDispatchable_fallbackToFailed_whenNoQueued() throws {
        var failed1 = PendingMessageLocal.alice(content: "f1", createdAt: 200)
        failed1.status = .failed
        var failed2 = PendingMessageLocal.alice(content: "f2", createdAt: 100)
        failed2.status = .failed
        _ = try dao.insert(failed1)
        _ = try dao.insert(failed2)
        let next = try dao.pickNextDispatchable(username: "alice")
        XCTAssertEqual(next?.content, "f2") // createdAt 更早
    }

    func test_pickNextDispatchable_emptyQueue_returnsNil() throws {
        XCTAssertNil(try dao.pickNextDispatchable(username: "alice"))
    }

    // MARK: - countDispatchable

    func test_countDispatchable_countsAllNonTransientStatuses() throws {
        _ = try dao.insert(.alice(content: "q1"))
        var sending = PendingMessageLocal.alice(content: "sending")
        sending.status = .sending
        _ = try dao.insert(sending)
        var failed = PendingMessageLocal.alice(content: "failed")
        failed.status = .failed
        _ = try dao.insert(failed)
        var processing = PendingMessageLocal.alice(content: "processing")
        processing.status = .processing
        _ = try dao.insert(processing) // PROCESSING 不计

        XCTAssertEqual(try dao.countDispatchable(username: "alice"), 3)
        XCTAssertEqual(try dao.countDispatchable(username: "bob"), 0)
    }

    // MARK: - update / delete / clear

    func test_update_changesStatusAndAttemptCount() throws {
        let id = try dao.insert(.alice(content: "x"))
        var loaded = try dao.findByLocalId(id)!
        loaded.status = .failed
        loaded.errorMessage = "boom"
        loaded.attemptCount = 2
        try dao.update(loaded)
        let after = try dao.findByLocalId(id)!
        XCTAssertEqual(after.status, .failed)
        XCTAssertEqual(after.errorMessage, "boom")
        XCTAssertEqual(after.attemptCount, 2)
    }

    func test_delete_removesRow() throws {
        let id = try dao.insert(.alice(content: "x"))
        try dao.delete(localId: id)
        XCTAssertNil(try dao.findByLocalId(id))
    }

    func test_clear_byUsername_doesNotAffectOtherUsers() throws {
        _ = try dao.insert(.alice(content: "a1"))
        _ = try dao.insert(.alice(content: "a2"))
        _ = try dao.insert(.bob(content: "b1"))
        try dao.clear(username: "alice")
        XCTAssertEqual(try dao.listAll(username: "alice"), [])
        XCTAssertEqual(try dao.listAll(username: "bob").map { $0.content }, ["b1"])
    }
}

private extension PendingMessageLocal {
    static func alice(content: String, createdAt: Int64 = 0) -> PendingMessageLocal {
        PendingMessageLocal(
            username: "alice",
            conversationKey: 7,
            content: content,
            status: .queued,
            createdAt: createdAt
        )
    }

    static func bob(content: String, createdAt: Int64 = 0) -> PendingMessageLocal {
        PendingMessageLocal(
            username: "bob",
            conversationKey: 7,
            content: content,
            status: .queued,
            createdAt: createdAt
        )
    }
}
