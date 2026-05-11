import XCTest
@testable import ThunderNote

final class FlashNoteEditViewModelTests: XCTestCase {
    @MainActor
    func test_canSubmit_falseWhenTitleEmpty() {
        let vm = FlashNoteEditViewModel(mode: .create, repository: StubEditRepo())
        vm.title = "   "
        XCTAssertFalse(vm.canSubmit)
        vm.title = "工作"
        XCTAssertTrue(vm.canSubmit)
    }

    @MainActor
    func test_create_returnsServerNoteAndClearsErrorOnSuccess() async {
        let repo = StubEditRepo()
        let vm = FlashNoteEditViewModel(mode: .create, repository: repo)
        vm.title = "新建"
        vm.icon = "💡"

        let result = await vm.submit()

        XCTAssertEqual(result?.title, "新建")
        XCTAssertEqual(result?.icon, "💡")
        XCTAssertEqual(repo.createCalls.count, 1)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func test_create_emptyTitleSurfacesError() async {
        let vm = FlashNoteEditViewModel(mode: .create, repository: StubEditRepo())
        vm.title = "   "
        let result = await vm.submit()
        XCTAssertNil(result)
        XCTAssertEqual(vm.errorMessage, "请输入闪记标题")
    }

    @MainActor
    func test_edit_initialStateMatchesProvidedNote() {
        let note = FlashNote(id: 7, title: "现有", icon: "📚", tags: "学习")
        let vm = FlashNoteEditViewModel(mode: .edit(note), repository: StubEditRepo())
        XCTAssertEqual(vm.title, "现有")
        XCTAssertEqual(vm.icon, "📚")
        XCTAssertEqual(vm.tags, "学习")
        XCTAssertTrue(vm.isEditing)
    }

    @MainActor
    func test_edit_callsUpdate() async {
        let repo = StubEditRepo()
        let note = FlashNote(id: 7, title: "现有", icon: "📚")
        let vm = FlashNoteEditViewModel(mode: .edit(note), repository: repo)
        vm.title = "改名"
        vm.tags = "工作"

        let result = await vm.submit()

        XCTAssertEqual(result?.id, 7)
        XCTAssertEqual(repo.updateCalls.count, 1)
        XCTAssertEqual(repo.updateCalls.first?.title, "改名")
        XCTAssertEqual(repo.updateCalls.first?.tags, "工作")
    }
}

private final class StubEditRepo: FlashNoteRepository, @unchecked Sendable {
    struct CreateCall { let title: String; let icon: String?; let tags: String? }
    struct UpdateCall { let id: Int64; let title: String; let icon: String?; let tags: String? }

    /// 用 `DispatchQueue.sync` 做同步：`NSLock.lock()` 在 Swift 6 严格并发下
    /// 在 async 上下文里是 unavailable。
    private let queue = DispatchQueue(label: "tn.tests.flashnote.editstub")
    private var _createCalls: [CreateCall] = []
    private var _updateCalls: [UpdateCall] = []

    var createCalls: [CreateCall] { queue.sync { _createCalls } }
    var updateCalls: [UpdateCall] { queue.sync { _updateCalls } }

    func list() async throws -> [FlashNote] { [] }
    func create(title: String, icon: String?, tags: String?) async throws -> FlashNote {
        let call = CreateCall(title: title, icon: icon, tags: tags)
        queue.sync { _createCalls.append(call) }
        return FlashNote(id: 1, title: title, icon: icon, tags: tags)
    }
    func update(id: Int64, title: String, icon: String?, tags: String?) async throws -> FlashNote {
        let call = UpdateCall(id: id, title: title, icon: icon, tags: tags)
        queue.sync { _updateCalls.append(call) }
        return FlashNote(id: id, title: title, icon: icon, tags: tags)
    }
    func setPinned(id: Int64, value: Bool) async throws {}
    func setHidden(id: Int64, value: Bool) async throws {}
    func delete(id: Int64) async throws {}
}
