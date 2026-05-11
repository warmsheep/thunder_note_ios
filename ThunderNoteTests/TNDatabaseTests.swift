import XCTest
@testable import ThunderNote

/// D2-I7 sqlite3 轻封装 + SyncMetaDao 单测。
final class TNDatabaseTests: XCTestCase {

    private var dbURL: URL!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tn-db-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("test.sqlite3")
    }

    override func tearDown() {
        if let url = dbURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        super.tearDown()
    }

    func test_openCreatesFile_andMigrationsRunOnce() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbURL.path))
        _ = try TNDatabase(fileURL: dbURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path))

        // 再次打开同一个文件不应该重跑 migration（user_version 已经到 latest）。
        let db2 = try TNDatabase(fileURL: dbURL)
        // 通过插入 + 查询验证 schema 可用。
        try db2.write { handle in
            try handle.execute(
                "INSERT INTO sync_meta(username, last_message_created_at, server_time) VALUES (?, ?, ?)",
                bindings: [.text("alice"), .text("2026-01-01T00:00:00"), .text("2026-01-01T00:00:01")]
            )
        }
        let username: String? = try db2.read { handle in
            try handle.queryFirst(
                "SELECT username FROM sync_meta WHERE username = ?",
                bindings: [.text("alice")]
            ) { row in row.text(0) } ?? nil
        }
        XCTAssertEqual(username, "alice")
    }

    func test_syncMetaDao_upsert_andRead() throws {
        let db = try TNDatabase(fileURL: dbURL)
        let dao = SQLiteSyncMetaDao(database: db)

        XCTAssertNil(try dao.loadLastMessageCreatedAt(username: "alice"))
        XCTAssertNil(try dao.loadServerTime(username: "alice"))

        try dao.upsert(
            username: "alice",
            lastMessageCreatedAt: "2026-05-01T10:00:00",
            serverTime: "2026-05-01T10:00:01"
        )
        XCTAssertEqual(try dao.loadLastMessageCreatedAt(username: "alice"), "2026-05-01T10:00:00")
        XCTAssertEqual(try dao.loadServerTime(username: "alice"), "2026-05-01T10:00:01")

        // upsert 单边更新：传 nil 不应覆盖现有值，由 COALESCE 兜底。
        try dao.upsert(username: "alice", lastMessageCreatedAt: nil, serverTime: "2026-05-01T11:00:00")
        XCTAssertEqual(try dao.loadLastMessageCreatedAt(username: "alice"), "2026-05-01T10:00:00")
        XCTAssertEqual(try dao.loadServerTime(username: "alice"), "2026-05-01T11:00:00")

        try dao.upsert(username: "alice", lastMessageCreatedAt: "2026-05-02T10:00:00", serverTime: nil)
        XCTAssertEqual(try dao.loadLastMessageCreatedAt(username: "alice"), "2026-05-02T10:00:00")
        XCTAssertEqual(try dao.loadServerTime(username: "alice"), "2026-05-01T11:00:00")
    }

    func test_syncMetaDao_multiUserIsolation() throws {
        let db = try TNDatabase(fileURL: dbURL)
        let dao = SQLiteSyncMetaDao(database: db)
        try dao.upsert(username: "alice", lastMessageCreatedAt: "A", serverTime: "AT")
        try dao.upsert(username: "bob", lastMessageCreatedAt: "B", serverTime: "BT")
        XCTAssertEqual(try dao.loadLastMessageCreatedAt(username: "alice"), "A")
        XCTAssertEqual(try dao.loadLastMessageCreatedAt(username: "bob"), "B")
        XCTAssertEqual(try dao.loadServerTime(username: "alice"), "AT")
        XCTAssertEqual(try dao.loadServerTime(username: "bob"), "BT")
    }

    func test_syncMetaDao_clear_removesRow() throws {
        let db = try TNDatabase(fileURL: dbURL)
        let dao = SQLiteSyncMetaDao(database: db)
        try dao.upsert(username: "alice", lastMessageCreatedAt: "A", serverTime: "AT")
        try dao.clear(username: "alice")
        XCTAssertNil(try dao.loadLastMessageCreatedAt(username: "alice"))
        XCTAssertNil(try dao.loadServerTime(username: "alice"))
    }

    func test_deleteFile_resetsDatabase() throws {
        let db = try TNDatabase(fileURL: dbURL)
        let dao = SQLiteSyncMetaDao(database: db)
        try dao.upsert(username: "alice", lastMessageCreatedAt: "A", serverTime: "AT")
        try db.deleteFile()
        XCTAssertNil(try dao.loadLastMessageCreatedAt(username: "alice"))
    }
}
