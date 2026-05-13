import XCTest
@testable import ThunderNote

final class FavoritesViewModelTests: XCTestCase {
    @MainActor
    func test_load_populatesItemsAndRegistry() async {
        let repo = StubFavoriteRepository(items: [
            FavoriteItem(id: 1, messageId: 10, flashNoteId: 7, favoritedAt: "2026-05-11T10:00:00"),
            FavoriteItem(id: 2, messageId: 11, flashNoteId: -1, flashNoteTitle: "收集箱", favoritedAt: "2026-05-11T12:00:00")
        ])
        let registry = FavoriteIdRegistry()
        let vm = FavoritesViewModel(repository: repo, registry: registry)

        await vm.load()

        XCTAssertEqual(vm.items.count, 2)
        // 按 favoritedAt 倒序：12:00 在前
        XCTAssertEqual(vm.items.first?.id, 2)
        XCTAssertEqual(registry.favoritedMessageIds, Set([10, 11]))
    }

    @MainActor
    func test_remove_dropsLocalAndUpdatesRegistry() async {
        let repo = StubFavoriteRepository(items: [
            FavoriteItem(id: 1, messageId: 10, flashNoteId: 7)
        ])
        let registry = FavoriteIdRegistry()
        let vm = FavoritesViewModel(repository: repo, registry: registry)
        await vm.load()

        await vm.remove(vm.items[0])

        XCTAssertEqual(repo.unfavoriteIds, [10])
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertFalse(registry.contains(10))
    }

    @MainActor
    func test_remove_missingMessageIdSurfacesError() async {
        let repo = StubFavoriteRepository(items: [
            FavoriteItem(id: 1, messageId: nil)
        ])
        let registry = FavoriteIdRegistry()
        let vm = FavoritesViewModel(repository: repo, registry: registry)
        await vm.load()

        await vm.remove(vm.items[0])

        XCTAssertEqual(repo.unfavoriteIds, [])
        XCTAssertNotNil(vm.transientMessage)
    }

    @MainActor
    func test_applySyncSnapshot_replacesItemsAndRegistry() {
        let repo = StubFavoriteRepository(items: [FavoriteItem(id: 1, messageId: 10)])
        let registry = FavoriteIdRegistry()
        let vm = FavoritesViewModel(repository: repo, registry: registry)

        vm.applySyncSnapshot([
            FavoriteItem(id: 2, messageId: 22, favoritedAt: "2026-05-13T11:00:00"),
            FavoriteItem(id: 3, messageId: 21, favoritedAt: "2026-05-13T10:00:00")
        ])

        XCTAssertEqual(vm.items.map(\.id), [2, 3])
        XCTAssertEqual(registry.favoritedMessageIds, Set([21, 22]))
    }
}

private final class StubFavoriteRepository: FavoriteRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.favorite.stub")
    private var _items: [FavoriteItem]
    private var _unfavoriteIds: [Int64] = []

    init(items: [FavoriteItem]) { _items = items }

    var unfavoriteIds: [Int64] { queue.sync { _unfavoriteIds } }

    func list() async throws -> [FavoriteItem] { queue.sync { _items } }
    func favorite(messageId: Int64) async throws -> FavoriteItem {
        FavoriteItem(id: 100, messageId: messageId)
    }
    func unfavorite(messageId: Int64) async throws {
        queue.sync { _unfavoriteIds.append(messageId) }
    }
}
