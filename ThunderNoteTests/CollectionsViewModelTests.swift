import XCTest
@testable import ThunderNote

final class CollectionsViewModelTests: XCTestCase {
    @MainActor
    func test_recomputeGroups_groupsByTagAndUncategorized() async {
        let collections: [Collection] = [
            Collection(id: 1, name: "工作"),
            Collection(id: 2, name: "学习")
        ]
        let notes: [FlashNote] = [
            FlashNote(id: -1, pinned: true, inbox: true),
            FlashNote(id: 10, title: "周报", tags: "工作"),
            FlashNote(id: 11, title: "笔记", tags: "学习"),
            FlashNote(id: 12, title: "灵感"),
            FlashNote(id: 13, title: "已隐藏", tags: "工作", hidden: true)
        ]
        let flashRepo = StubFlashNoteRepository(notes: notes)
        let flashVM = FlashNoteListViewModel(repository: flashRepo)
        await flashVM.load()

        let collRepo = StubCollectionRepository(collections: collections)
        let vm = CollectionsViewModel(collectionRepository: collRepo, flashNoteListViewModel: flashVM)
        await vm.load()

        XCTAssertEqual(vm.groups.count, 3, "工作 / 学习 + 未分类")
        let byName = Dictionary(uniqueKeysWithValues: vm.groups.map { ($0.displayName, $0) })
        XCTAssertEqual(byName["工作"]?.notes.map(\.id), [10], "隐藏闪记应被排除")
        XCTAssertEqual(byName["学习"]?.notes.map(\.id), [11])
        XCTAssertEqual(byName["未分类"].map { Set($0.notes.map(\.id)) }, Set([-1, 12]), "收集箱与无 tag 闪记一起进入未分类")
        // 「未分类」永远排在最后；其余按 displayName 排序。
        XCTAssertEqual(vm.groups.last?.displayName, "未分类")
    }

    @MainActor
    func test_createCollection_appendsAndResorts() async {
        let collRepo = StubCollectionRepository(collections: [Collection(id: 1, name: "Z")])
        let flashVM = FlashNoteListViewModel(repository: StubFlashNoteRepository(notes: []))
        await flashVM.load()
        let vm = CollectionsViewModel(collectionRepository: collRepo, flashNoteListViewModel: flashVM)
        await vm.load()

        let created = await vm.createCollection(name: "A")

        XCTAssertNotNil(created)
        XCTAssertEqual(vm.collections.map { $0.name }, ["A", "Z"], "按名称排序")
    }
}

// MARK: - Stubs

private final class StubCollectionRepository: CollectionRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.collection.stub")
    private var _collections: [Collection]

    init(collections: [Collection]) { self._collections = collections }

    func list() async throws -> [Collection] { queue.sync { _collections } }

    func create(name: String) async throws -> Collection {
        let next = (queue.sync { _collections.map { $0.id }.max() } ?? 0) + 1
        let created = Collection(id: next, name: name)
        queue.sync { _collections.append(created) }
        return created
    }

    func update(id: Int64, name: String) async throws -> Collection {
        Collection(id: id, name: name)
    }

    func delete(id: Int64) async throws {
        queue.sync { _collections.removeAll { $0.id == id } }
    }
}

private final class StubFlashNoteRepository: FlashNoteRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.flashnote.collstub")
    private var _notes: [FlashNote]

    init(notes: [FlashNote]) { self._notes = notes }

    func list() async throws -> [FlashNote] { queue.sync { _notes } }
    func create(title: String, icon: String?, tags: String?) async throws -> FlashNote {
        FlashNote(id: 1, title: title, icon: icon, tags: tags)
    }
    func update(id: Int64, title: String, icon: String?, tags: String?) async throws -> FlashNote {
        FlashNote(id: id, title: title, icon: icon, tags: tags)
    }
    func setPinned(id: Int64, value: Bool) async throws {}
    func setHidden(id: Int64, value: Bool) async throws {}
    func delete(id: Int64) async throws {}
}
