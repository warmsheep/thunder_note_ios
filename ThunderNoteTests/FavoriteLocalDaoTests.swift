import XCTest
@testable import ThunderNote

/// D2-I7 FavoriteLocalDao 单测。
final class FavoriteLocalDaoTests: XCTestCase {

    private var dbURL: URL!
    private var database: TNDatabase!
    private var dao: SQLiteFavoriteLocalDao!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tn-favlocal-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("fav.sqlite3")
        database = try! TNDatabase(fileURL: dbURL)
        dao = SQLiteFavoriteLocalDao(database: database)
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
        let fav = FavoriteItem(
            id: 100,
            messageId: 200,
            flashNoteId: 7,
            flashNoteTitle: "工作",
            flashNoteIcon: "📝",
            role: "USER",
            content: "hello",
            mediaType: "TEXT",
            mediaUrl: nil,
            fileName: nil,
            fileSize: nil,
            mediaDuration: nil,
            favoritedAt: "2026-05-13T10:00:00",
            messageCreatedAt: "2026-05-13T09:00:00"
        )
        try dao.upsert(fav, username: "alice")
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].id, 100)
        XCTAssertEqual(list[0].messageId, 200)
        XCTAssertEqual(list[0].flashNoteTitle, "工作")
        XCTAssertEqual(list[0].flashNoteIcon, "📝")
        XCTAssertEqual(list[0].role, "USER")
        XCTAssertEqual(list[0].content, "hello")
        XCTAssertEqual(list[0].favoritedAt, "2026-05-13T10:00:00")
    }

    func test_upsert_withPayload_roundTrips() throws {
        let payload = CardPayload(
            cardType: "MESSAGE_COLLECTION",
            title: "卡片标题",
            summary: "摘要",
            items: [
                CardItem(originalMsgId: 1, mediaType: "TEXT", content: "卡片内容")
            ]
        )
        let fav = FavoriteItem(
            id: 100,
            messageId: 200,
            content: "卡片消息",
            payload: payload
        )
        try dao.upsert(fav, username: "alice")
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].payload?.cardType, "MESSAGE_COLLECTION")
        XCTAssertEqual(list[0].payload?.title, "卡片标题")
        XCTAssertEqual(list[0].payload?.items?.count, 1)
        XCTAssertEqual(list[0].payload?.items?.first?.content, "卡片内容")
    }

    func test_replaceAll_overwritesExistingData() throws {
        try dao.upsert(FavoriteItem(id: 1, content: "旧数据", favoritedAt: "2026-01-01T00:00:00"), username: "alice")
        let newFavs = [
            FavoriteItem(id: 2, content: "新A", favoritedAt: "2026-05-13T10:00:00"),
            FavoriteItem(id: 3, content: "新B", favoritedAt: "2026-05-13T11:00:00")
        ]
        try dao.replaceAll(newFavs, username: "alice")
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(Set(list.map { $0.id }), [2, 3])
    }

    func test_listAll_filtersByUsername() throws {
        try dao.upsert(FavoriteItem(id: 1, content: "alice-fav"), username: "alice")
        try dao.upsert(FavoriteItem(id: 1, content: "bob-fav"), username: "bob")
        XCTAssertEqual(try dao.listAll(username: "alice").first?.content, "alice-fav")
        XCTAssertEqual(try dao.listAll(username: "bob").first?.content, "bob-fav")
    }

    func test_upsert_replacesByPrimaryKey() throws {
        try dao.upsert(
            FavoriteItem(id: 1, content: "v1", favoritedAt: "2026-01-01T00:00:00"),
            username: "alice"
        )
        try dao.upsert(
            FavoriteItem(id: 1, content: "v2", favoritedAt: "2026-01-01T00:00:01"),
            username: "alice"
        )
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.content, "v2")
    }

    // MARK: - delete

    func test_delete_removesSpecificFavorite() throws {
        try dao.upsert(FavoriteItem(id: 1, content: "a"), username: "alice")
        try dao.upsert(FavoriteItem(id: 2, content: "b"), username: "alice")
        try dao.delete(username: "alice", id: 1)
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.id, 2)
    }

    func test_deleteByMessageId_removesByMessageId() throws {
        try dao.upsert(FavoriteItem(id: 1, messageId: 100, content: "a"), username: "alice")
        try dao.upsert(FavoriteItem(id: 2, messageId: 200, content: "b"), username: "alice")
        try dao.deleteByMessageId(username: "alice", messageId: 100)
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.messageId, 200)
    }

    // MARK: - clear

    func test_clear_removesAllForUsername() throws {
        try dao.upsert(FavoriteItem(id: 1, content: "a"), username: "alice")
        try dao.upsert(FavoriteItem(id: 2, content: "b"), username: "alice")
        try dao.upsert(FavoriteItem(id: 1, content: "c"), username: "bob")
        try dao.clear(username: "alice")
        XCTAssertEqual(try dao.listAll(username: "alice").count, 0)
        XCTAssertEqual(try dao.listAll(username: "bob").count, 1)
    }
}
