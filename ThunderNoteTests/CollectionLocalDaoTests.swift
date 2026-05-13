import XCTest
@testable import ThunderNote

/// D2-I7 CollectionLocalDao 单测。
final class CollectionLocalDaoTests: XCTestCase {

    private var dbURL: URL!
    private var database: TNDatabase!
    private var dao: SQLiteCollectionLocalDao!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tn-collocal-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("col.sqlite3")
        database = try! TNDatabase(fileURL: dbURL)
        dao = SQLiteCollectionLocalDao(database: database)
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
        let col = Collection(
            id: 100,
            userId: 1,
            name: "工作",
            description: "工作相关",
            createdAt: "2026-05-13T10:00:00",
            updatedAt: "2026-05-13T10:00:01"
        )
        try dao.upsert(col, username: "alice")
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].id, 100)
        XCTAssertEqual(list[0].name, "工作")
        XCTAssertEqual(list[0].description, "工作相关")
        XCTAssertEqual(list[0].createdAt, "2026-05-13T10:00:00")
    }

    func test_replaceAll_overwritesExistingData() throws {
        try dao.upsert(Collection(id: 1, name: "旧数据"), username: "alice")
        let newCols = [
            Collection(id: 2, name: "新数据A"),
            Collection(id: 3, name: "新数据B")
        ]
        try dao.replaceAll(newCols, username: "alice")
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(Set(list.map { $0.id }), [2, 3])
    }

    func test_listAll_filtersByUsername() throws {
        try dao.upsert(Collection(id: 1, name: "alice-col"), username: "alice")
        try dao.upsert(Collection(id: 1, name: "bob-col"), username: "bob")
        XCTAssertEqual(try dao.listAll(username: "alice").first?.name, "alice-col")
        XCTAssertEqual(try dao.listAll(username: "bob").first?.name, "bob-col")
    }

    func test_upsert_replacesByPrimaryKey() throws {
        try dao.upsert(Collection(id: 1, name: "v1"), username: "alice")
        try dao.upsert(Collection(id: 1, name: "v2"), username: "alice")
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.name, "v2")
    }

    // MARK: - delete

    func test_delete_removesSpecificCollection() throws {
        try dao.upsert(Collection(id: 1, name: "a"), username: "alice")
        try dao.upsert(Collection(id: 2, name: "b"), username: "alice")
        try dao.delete(username: "alice", id: 1)
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.id, 2)
    }

    // MARK: - clear

    func test_clear_removesAllForUsername() throws {
        try dao.upsert(Collection(id: 1, name: "a"), username: "alice")
        try dao.upsert(Collection(id: 2, name: "b"), username: "alice")
        try dao.upsert(Collection(id: 1, name: "c"), username: "bob")
        try dao.clear(username: "alice")
        XCTAssertEqual(try dao.listAll(username: "alice").count, 0)
        XCTAssertEqual(try dao.listAll(username: "bob").count, 1)
    }

    // MARK: - ordering

    func test_listAll_ordersByNameCaseInsensitive() throws {
        try dao.upsert(Collection(id: 1, name: "Banana"), username: "alice")
        try dao.upsert(Collection(id: 2, name: "apple"), username: "alice")
        try dao.upsert(Collection(id: 3, name: "Cherry"), username: "alice")
        let list = try dao.listAll(username: "alice")
        XCTAssertEqual(list.map { $0.name }, ["apple", "Banana", "Cherry"])
    }
}
