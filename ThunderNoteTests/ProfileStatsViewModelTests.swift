import XCTest
@testable import ThunderNote

/// D2-I6-08 ProfileStatsViewModel 单元测试。
final class ProfileStatsViewModelTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "tn.tests.profile.stats"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    @MainActor
    func test_init_loadsCachedStatsForCurrentUser() {
        // 预先把缓存写入
        let stats = ProfileStatsViewModel.Stats(flashNoteCount: 5, favoriteCount: 3, recordCount: 999)
        if let data = try? JSONEncoder.tnDefault.encode(stats) {
            defaults.set(data, forKey: ProfileStatsViewModel.cacheKey(for: "alice"))
        }
        let vm = ProfileStatsViewModel(
            flashNoteRepository: StubFlashNoteRepo(),
            favoriteRepository: StubFavoriteRepo(),
            messageRepository: StubMessageRepo(),
            userDefaults: defaults,
            usernameProvider: { "alice" }
        )
        XCTAssertEqual(vm.stats.flashNoteCount, 5)
        XCTAssertEqual(vm.stats.favoriteCount, 3)
        XCTAssertEqual(vm.stats.recordCount, 999)
    }

    @MainActor
    func test_refresh_aggregatesAndPersists() async {
        let vm = ProfileStatsViewModel(
            flashNoteRepository: StubFlashNoteRepo(count: 7),
            favoriteRepository: StubFavoriteRepo(count: 4),
            messageRepository: StubMessageRepo(recordCount: 12345),
            userDefaults: defaults,
            usernameProvider: { "alice" }
        )
        await vm.refresh()
        XCTAssertEqual(vm.stats.flashNoteCount, 7)
        XCTAssertEqual(vm.stats.favoriteCount, 4)
        XCTAssertEqual(vm.stats.recordCount, 12345)
        // 持久化校验：换一个 VM 读取
        let vm2 = ProfileStatsViewModel(
            flashNoteRepository: StubFlashNoteRepo(),
            favoriteRepository: StubFavoriteRepo(),
            messageRepository: StubMessageRepo(),
            userDefaults: defaults,
            usernameProvider: { "alice" }
        )
        XCTAssertEqual(vm2.stats.flashNoteCount, 7)
        XCTAssertEqual(vm2.stats.recordCount, 12345)
    }

    @MainActor
    func test_refresh_ignoresFailuresAndZeroFills() async {
        let vm = ProfileStatsViewModel(
            flashNoteRepository: ThrowingFlashNoteRepo(),
            favoriteRepository: ThrowingFavoriteRepo(),
            messageRepository: ThrowingMessageRepo(),
            userDefaults: defaults,
            usernameProvider: { "alice" }
        )
        await vm.refresh()
        XCTAssertEqual(vm.stats.flashNoteCount, 0)
        XCTAssertEqual(vm.stats.favoriteCount, 0)
        XCTAssertEqual(vm.stats.recordCount, 0)
    }

    @MainActor
    func test_clearCache_removesUserDefaultsAndResetsState() async {
        let vm = ProfileStatsViewModel(
            flashNoteRepository: StubFlashNoteRepo(count: 1),
            favoriteRepository: StubFavoriteRepo(count: 1),
            messageRepository: StubMessageRepo(recordCount: 1),
            userDefaults: defaults,
            usernameProvider: { "alice" }
        )
        await vm.refresh()
        XCTAssertEqual(vm.stats.flashNoteCount, 1)
        vm.clearCache()
        XCTAssertEqual(vm.stats.flashNoteCount, 0)
        XCTAssertNil(defaults.data(forKey: ProfileStatsViewModel.cacheKey(for: "alice")))
    }
}

// MARK: - Stubs

private final class StubFlashNoteRepo: FlashNoteRepository, @unchecked Sendable {
    private let count: Int
    init(count: Int = 0) { self.count = count }
    func list() async throws -> [FlashNote] {
        (0..<count).map { idx in
            FlashNote(id: Int64(idx + 1), title: "n\(idx)")
        }
    }
    func create(title: String, icon: String?, tags: String?) async throws -> FlashNote {
        FlashNote(id: 1, title: title)
    }
    func update(id: Int64, title: String, icon: String?, tags: String?) async throws -> FlashNote {
        FlashNote(id: id, title: title, icon: icon, tags: tags)
    }
    func setPinned(id: Int64, value: Bool) async throws {}
    func setHidden(id: Int64, value: Bool) async throws {}
    func delete(id: Int64) async throws {}
    func search(query: String) async throws -> FlashNoteSearchResponse {
        FlashNoteSearchResponse(noteNameMatched: [], messageContentMatched: [])
    }
}

private final class ThrowingFlashNoteRepo: FlashNoteRepository, @unchecked Sendable {
    func list() async throws -> [FlashNote] { throw APIError.business(code: 500, message: "x") }
    func create(title: String, icon: String?, tags: String?) async throws -> FlashNote {
        throw APIError.business(code: 500, message: "x")
    }
    func update(id: Int64, title: String, icon: String?, tags: String?) async throws -> FlashNote {
        throw APIError.business(code: 500, message: "x")
    }
    func setPinned(id: Int64, value: Bool) async throws { throw APIError.business(code: 500, message: "x") }
    func setHidden(id: Int64, value: Bool) async throws { throw APIError.business(code: 500, message: "x") }
    func delete(id: Int64) async throws { throw APIError.business(code: 500, message: "x") }
    func search(query: String) async throws -> FlashNoteSearchResponse {
        throw APIError.business(code: 500, message: "x")
    }
}

private final class StubFavoriteRepo: FavoriteRepository, @unchecked Sendable {
    private let count: Int
    init(count: Int = 0) { self.count = count }
    func list() async throws -> [FavoriteItem] {
        (0..<count).map { idx in
            FavoriteItem(id: Int64(idx + 1), messageId: Int64(idx + 1))
        }
    }
    func favorite(messageId: Int64) async throws -> FavoriteItem {
        FavoriteItem(id: 1, messageId: messageId)
    }
    func unfavorite(messageId: Int64) async throws {}
}

private final class ThrowingFavoriteRepo: FavoriteRepository, @unchecked Sendable {
    func list() async throws -> [FavoriteItem] { throw APIError.business(code: 500, message: "x") }
    func favorite(messageId: Int64) async throws -> FavoriteItem {
        throw APIError.business(code: 500, message: "x")
    }
    func unfavorite(messageId: Int64) async throws { throw APIError.business(code: 500, message: "x") }
}

private final class StubMessageRepo: MessageRepository, @unchecked Sendable {
    private let recordCount: Int64
    init(recordCount: Int64 = 0) { self.recordCount = recordCount }
    func listMessages(key: ConversationKey, page: Int, limit: Int) async throws -> PageData<Message> {
        PageData(records: [], total: 0, size: Int64(limit), current: Int64(page), pages: 0)
    }
    func send(_ message: Message) async throws -> Message { message }
    func delete(id: Int64) async throws {}
    func deleteBatch(ids: [Int64]) async throws {}
    func clearInbox() async throws {}
    func merge(_ request: MessageMergeRequest) async throws -> Message {
        Message(id: 1, content: request.title, mediaType: "COMPOSITE")
    }
    func createComposite(_ request: CompositeMessageRequest) async throws -> Message {
        Message(id: 1, content: request.title, mediaType: "COMPOSITE")
    }
    func countMessages() async throws -> Int64 { recordCount }
}

private final class ThrowingMessageRepo: MessageRepository, @unchecked Sendable {
    func listMessages(key: ConversationKey, page: Int, limit: Int) async throws -> PageData<Message> {
        throw APIError.business(code: 500, message: "x")
    }
    func send(_ message: Message) async throws -> Message {
        throw APIError.business(code: 500, message: "x")
    }
    func delete(id: Int64) async throws { throw APIError.business(code: 500, message: "x") }
    func deleteBatch(ids: [Int64]) async throws { throw APIError.business(code: 500, message: "x") }
    func clearInbox() async throws { throw APIError.business(code: 500, message: "x") }
    func merge(_ request: MessageMergeRequest) async throws -> Message {
        throw APIError.business(code: 500, message: "x")
    }
    func createComposite(_ request: CompositeMessageRequest) async throws -> Message {
        throw APIError.business(code: 500, message: "x")
    }
    func countMessages() async throws -> Int64 { throw APIError.business(code: 500, message: "x") }
}
