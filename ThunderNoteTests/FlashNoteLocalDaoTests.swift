import XCTest
@testable import ThunderNote

/// D2-I7 FlashNoteLocalDao 单测。
final class FlashNoteLocalDaoTests: XCTestCase {

    private var dbURL: URL!
    private var database: TNDatabase!
    private var dao: SQLiteFlashNoteLocalDao!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tn-fnlocal-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("fn.sqlite3")
        database = try! TNDatabase(fileURL: dbURL)
        dao = SQLiteFlashNoteLocalDao(database: database)
    }

    override func tearDown() {
        dao = nil
        database = nil
        if let url = dbURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        super.tearDown()
    }

    // MARK: - upsert / listAll

    func test_upsert_thenListAll_returnsRoundTripValues() throws {
        let note = FlashNote(
            id: 100,
            userId: 1,
            title: "测试闪记",
            icon: "📝",
            content: "内容",
            latestMessage: "最新消息",
            tags: "tag1",
            deleted: false,
            pinned: true,
            hidden: false,
            inbox: false,
            createdAt: "2026-05-13T10:00:00",
            updatedAt: "2026-05-13T10:00:01"
        )
        try dao.upsert(note, username: "alice")
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].id, 100)
        XCTAssertEqual(list[0].title, "测试闪记")
        XCTAssertEqual(list[0].icon, "📝")
        XCTAssertEqual(list[0].content, "内容")
        XCTAssertEqual(list[0].pinned, true)
        XCTAssertEqual(list[0].deleted, false)
        XCTAssertEqual(list[0].inbox, false)
        XCTAssertEqual(list[0].createdAt, "2026-05-13T10:00:00")
    }

    func test_replaceAll_overwritesExistingData() throws {
        try dao.upsert(
            FlashNote(id: 1, title: "旧数据", updatedAt: "2026-01-01T00:00:00"),
            username: "alice"
        )
        let newNotes = [
            FlashNote(id: 2, title: "新数据A", updatedAt: "2026-05-13T00:00:00"),
            FlashNote(id: 3, title: "新数据B", updatedAt: "2026-05-13T01:00:00")
        ]
        try dao.replaceAll(newNotes, username: "alice")
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(Set(list.map { $0.id }), [2, 3])
    }

    func test_listAll_filtersByUsername() throws {
        try dao.upsert(FlashNote(id: 1, title: "alice"), username: "alice")
        try dao.upsert(FlashNote(id: 1, title: "bob"), username: "bob")
        XCTAssertEqual(try dao.listAll(username: "alice").first?.title, "alice")
        XCTAssertEqual(try dao.listAll(username: "bob").first?.title, "bob")
    }

    func test_upsert_replacesByPrimaryKey() throws {
        try dao.upsert(
            FlashNote(id: 1, title: "v1", updatedAt: "2026-01-01T00:00:00"),
            username: "alice"
        )
        try dao.upsert(
            FlashNote(id: 1, title: "v2", updatedAt: "2026-01-01T00:00:01"),
            username: "alice"
        )
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.title, "v2")
    }

    // MARK: - delete

    func test_delete_removesSpecificNote() throws {
        try dao.upsert(FlashNote(id: 1, title: "a", updatedAt: "2026-01-01T00:00:00"), username: "alice")
        try dao.upsert(FlashNote(id: 2, title: "b", updatedAt: "2026-01-01T00:00:00"), username: "alice")
        try dao.delete(username: "alice", id: 1)
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.id, 2)
    }

    func test_delete_doesNotAffectOtherUsers() throws {
        try dao.upsert(FlashNote(id: 1, title: "a"), username: "alice")
        try dao.upsert(FlashNote(id: 1, title: "b"), username: "bob")
        try dao.delete(username: "alice", id: 1)
        XCTAssertEqual(try dao.listAll(username: "alice").count, 0)
        XCTAssertEqual(try dao.listAll(username: "bob").count, 1)
    }

    // MARK: - clear

    func test_clear_removesAllForUsername() throws {
        try dao.upsert(FlashNote(id: 1, title: "a"), username: "alice")
        try dao.upsert(FlashNote(id: 2, title: "b"), username: "alice")
        try dao.upsert(FlashNote(id: 1, title: "c"), username: "bob")
        try dao.clear(username: "alice")
        XCTAssertEqual(try dao.listAll(username: "alice").count, 0)
        XCTAssertEqual(try dao.listAll(username: "bob").count, 1)
    }

    // MARK: - ordering

    func test_listAll_ordersByInboxFirstThenPinnedThenUpdatedAt() throws {
        try dao.upsert(
            FlashNote(id: 10, title: "普通", pinned: false, inbox: false, updatedAt: "2026-05-13T12:00:00"),
            username: "alice"
        )
        try dao.upsert(
            FlashNote(id: 20, title: "置顶", pinned: true, inbox: false, updatedAt: "2026-05-13T10:00:00"),
            username: "alice"
        )
        try dao.upsert(
            FlashNote(id: -1, title: "收集箱", pinned: false, inbox: true, updatedAt: "2026-05-13T08:00:00"),
            username: "alice"
        )
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list[0].id, -1)
        XCTAssertEqual(list[1].id, 20)
        XCTAssertEqual(list[2].id, 10)
    }
}
