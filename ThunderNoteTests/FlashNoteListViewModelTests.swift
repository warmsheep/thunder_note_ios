import XCTest
@testable import ThunderNote

final class FlashNoteListViewModelTests: XCTestCase {
    @MainActor
    func test_sort_putsInboxFirstThenPinnedThenByUpdatedAt() {
        let inbox = FlashNote(id: -1, title: "收集箱", pinned: true, inbox: true)
        let pinned = FlashNote(id: 1, title: "工作", pinned: true, updatedAt: "2026-05-01T10:00:00")
        let regularNew = FlashNote(id: 2, title: "新", updatedAt: "2026-05-03T10:00:00")
        let regularOld = FlashNote(id: 3, title: "旧", updatedAt: "2026-04-01T10:00:00")

        let sorted = FlashNoteListViewModel.sort([regularOld, regularNew, inbox, pinned])

        XCTAssertEqual(sorted[0].id, -1, "收集箱应始终置顶")
        XCTAssertEqual(sorted[1].id, 1, "其他置顶项次之")
        XCTAssertEqual(sorted[2].id, 2, "非置顶按 updatedAt 倒序")
        XCTAssertEqual(sorted[3].id, 3)
    }

    @MainActor
    func test_visibleNotes_filtersHiddenButKeepsInbox() async {
        let repo = StubFlashNoteRepository(notes: [
            FlashNote(id: -1, pinned: true, inbox: true),
            FlashNote(id: 1, title: "可见"),
            FlashNote(id: 2, title: "已隐藏", hidden: true)
        ])
        let vm = FlashNoteListViewModel(repository: repo)
        await vm.load()

        XCTAssertEqual(vm.visibleNotes.map(\FlashNote.id), [-1, 1])
    }

    @MainActor
    func test_togglePinned_updatesLocalState() async {
        let repo = StubFlashNoteRepository(notes: [
            FlashNote(id: 1, title: "x", pinned: false)
        ])
        let vm = FlashNoteListViewModel(repository: repo)
        await vm.load()
        let target = vm.notes.first(where: { $0.id == 1 })!

        await vm.togglePinned(target)

        XCTAssertEqual(repo.pinnedCalls, [PinnedCall(id: 1, value: true)])
        XCTAssertEqual(vm.note(byId: 1)?.isPinned, true)
    }

    @MainActor
    func test_toggleHidden_clearsPinnedLocally() async {
        let repo = StubFlashNoteRepository(notes: [
            FlashNote(id: 1, title: "x", pinned: true)
        ])
        let vm = FlashNoteListViewModel(repository: repo)
        await vm.load()
        let target = vm.note(byId: 1)!

        await vm.toggleHidden(target)

        XCTAssertEqual(vm.note(byId: 1)?.isHidden, true)
        XCTAssertEqual(vm.note(byId: 1)?.isPinned, false, "隐藏会自动取消置顶（与后端行为一致）")
    }

    @MainActor
    func test_delete_inboxIsRejectedWithToast() async {
        let repo = StubFlashNoteRepository(notes: [FlashNote(id: -1, inbox: true)])
        let vm = FlashNoteListViewModel(repository: repo)
        await vm.load()
        let inbox = vm.note(byId: -1)!

        await vm.delete(inbox)

        XCTAssertEqual(repo.deleteCalls.count, 0, "收集箱不应触发后端删除")
        XCTAssertEqual(vm.transientMessage, "收集箱不可删除")
        XCTAssertNotNil(vm.note(byId: -1), "收集箱依然存在")
    }

    @MainActor
    func test_delete_normalNoteIsRemovedLocally() async {
        let repo = StubFlashNoteRepository(notes: [
            FlashNote(id: 1, title: "x")
        ])
        let vm = FlashNoteListViewModel(repository: repo)
        await vm.load()
        let target = vm.note(byId: 1)!

        await vm.delete(target)

        XCTAssertEqual(repo.deleteCalls, [1])
        XCTAssertNil(vm.note(byId: 1))
    }

    @MainActor
    func test_load_setsErrorStateOnAPIFailure() async {
        let repo = StubFlashNoteRepository(notes: [], failOnList: APIError.business(code: 50000, message: "服务器错误"))
        let vm = FlashNoteListViewModel(repository: repo)
        await vm.load()
        if case .error(let message) = vm.state {
            XCTAssertEqual(message, "服务器错误")
        } else {
            XCTFail("应进入 error 状态：\(vm.state)")
        }
    }

    // MARK: - D2-I2-11 清空收集箱

    @MainActor
    func test_clearInbox_callsRepoAndClearsLatestMessageLocally() async {
        let repo = StubFlashNoteRepository(notes: [
            FlashNote(id: -1, latestMessage: "旧预览", inbox: true),
            FlashNote(id: 1, title: "其他")
        ])
        let msgRepo = StubInboxClearingMessageRepository()
        let vm = FlashNoteListViewModel(
            repository: repo,
            messageRepository: msgRepo
        )
        await vm.load()

        await vm.clearInbox()

        XCTAssertEqual(msgRepo.clearInboxCallCount, 1)
        XCTAssertNil(vm.note(byId: -1)?.latestMessage, "成功后本地预览应被抹掉")
        XCTAssertNil(vm.transientMessage)
        XCTAssertFalse(vm.isClearingInbox)
    }

    @MainActor
    func test_clearInbox_apiFailureSetsTransientAndKeepsLatestMessage() async {
        let repo = StubFlashNoteRepository(notes: [
            FlashNote(id: -1, latestMessage: "保留预览", inbox: true)
        ])
        let msgRepo = StubInboxClearingMessageRepository(
            failOnClearInbox: APIError.business(code: 50000, message: "清空失败")
        )
        let vm = FlashNoteListViewModel(
            repository: repo,
            messageRepository: msgRepo
        )
        await vm.load()

        await vm.clearInbox()

        XCTAssertEqual(vm.transientMessage, "清空失败")
        XCTAssertEqual(vm.note(byId: -1)?.latestMessage, "保留预览", "失败时不应抹掉本地预览")
        XCTAssertFalse(vm.isClearingInbox, "无论成败 isClearingInbox 都必须复位")
    }

    @MainActor
    func test_clearInbox_withoutMessageRepository_setsTransientMessage() async {
        let repo = StubFlashNoteRepository(notes: [
            FlashNote(id: -1, inbox: true)
        ])
        // 没传 messageRepository，模拟未配置场景
        let vm = FlashNoteListViewModel(repository: repo)
        await vm.load()

        await vm.clearInbox()

        XCTAssertEqual(vm.transientMessage, "消息仓库未初始化，无法清空收集箱")
    }

    // MARK: - D2-I2-12 收集箱预览本地更新

    @MainActor
    func test_updateInboxPreviewLocally_writesTrimmedTextAndUpdatesUpdatedAt() async {
        let repo = StubFlashNoteRepository(notes: [
            FlashNote(
                id: -1,
                latestMessage: "旧预览",
                inbox: true,
                updatedAt: "2020-01-01T00:00:00"
            )
        ])
        let vm = FlashNoteListViewModel(
            repository: repo,
            messageRepository: StubInboxClearingMessageRepository()
        )
        await vm.load()

        vm.updateInboxPreviewLocally("  快速捕获文本   ")

        XCTAssertEqual(vm.note(byId: -1)?.latestMessage, "快速捕获文本")
        XCTAssertNotEqual(
            vm.note(byId: -1)?.updatedAt,
            "2020-01-01T00:00:00",
            "updatedAt 应被刷成本地当前时间"
        )
    }

    @MainActor
    func test_updateInboxPreviewLocally_blankInputIsIgnored() async {
        let repo = StubFlashNoteRepository(notes: [
            FlashNote(
                id: -1,
                latestMessage: "旧预览",
                inbox: true,
                updatedAt: "2020-01-01T00:00:00"
            )
        ])
        let vm = FlashNoteListViewModel(
            repository: repo,
            messageRepository: StubInboxClearingMessageRepository()
        )
        await vm.load()

        vm.updateInboxPreviewLocally(nil)
        vm.updateInboxPreviewLocally("")
        vm.updateInboxPreviewLocally("    ")

        XCTAssertEqual(vm.note(byId: -1)?.latestMessage, "旧预览", "空白输入应被忽略")
        XCTAssertEqual(vm.note(byId: -1)?.updatedAt, "2020-01-01T00:00:00")
    }

    @MainActor
    func test_upsertCreated_insertsAndResorts() async {
        let repo = StubFlashNoteRepository(notes: [
            FlashNote(id: -1, pinned: true, inbox: true),
            FlashNote(id: 1, title: "旧", updatedAt: "2026-01-01T00:00:00")
        ])
        let vm = FlashNoteListViewModel(repository: repo)
        await vm.load()

        let newNote = FlashNote(id: 99, title: "新", updatedAt: "2026-12-01T00:00:00")
        vm.upsertCreated(newNote)

        XCTAssertEqual(vm.notes.first?.id, -1, "收集箱仍在最前")
        XCTAssertEqual(vm.notes.dropFirst().first?.id, 99, "新建项排在更新时间最近的位置")
    }
}

// MARK: - Stub Repository

private struct PinnedCall: Equatable {
    let id: Int64
    let value: Bool
}

private final class StubFlashNoteRepository: FlashNoteRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.flashnote.liststub")
    private var _notes: [FlashNote]
    private var _pinnedCalls: [PinnedCall] = []
    private var _hiddenCalls: [PinnedCall] = []
    private var _deleteCalls: [Int64] = []
    private var _failOnList: APIError?

    init(notes: [FlashNote], failOnList: APIError? = nil) {
        self._notes = notes
        self._failOnList = failOnList
    }

    var pinnedCalls: [PinnedCall] { queue.sync { _pinnedCalls } }
    var deleteCalls: [Int64] { queue.sync { _deleteCalls } }

    func list() async throws -> [FlashNote] {
        let snapshot: (notes: [FlashNote], err: APIError?) = queue.sync { (_notes, _failOnList) }
        if let err = snapshot.err { throw err }
        return snapshot.notes
    }

    func create(title: String, icon: String?, tags: String?) async throws -> FlashNote {
        FlashNote(id: 100, title: title, icon: icon, tags: tags)
    }

    func update(id: Int64, title: String, icon: String?, tags: String?) async throws -> FlashNote {
        FlashNote(id: id, title: title, icon: icon, tags: tags)
    }

    func setPinned(id: Int64, value: Bool) async throws {
        let call = PinnedCall(id: id, value: value)
        queue.sync { _pinnedCalls.append(call) }
    }

    func setHidden(id: Int64, value: Bool) async throws {
        let call = PinnedCall(id: id, value: value)
        queue.sync { _hiddenCalls.append(call) }
    }

    func delete(id: Int64) async throws {
        queue.sync { _deleteCalls.append(id) }
    }
}

/// 仅用于覆盖 D2-I2-11 / D2-I2-12 用到的 `MessageRepository.clearInbox()`，
/// 其余成员维持空实现 / 占位返回值。
private final class StubInboxClearingMessageRepository: MessageRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.flashnote.inboxstub")
    private var _clearInboxCallCount: Int = 0
    private var _failOnClearInbox: APIError?

    init(failOnClearInbox: APIError? = nil) {
        self._failOnClearInbox = failOnClearInbox
    }

    var clearInboxCallCount: Int {
        queue.sync { _clearInboxCallCount }
    }

    func listMessages(key: ConversationKey, page: Int, limit: Int) async throws -> PageData<Message> {
        PageData(records: [], total: 0, size: Int64(limit), current: 1, pages: 1)
    }
    func send(_ message: Message) async throws -> Message { message }
    func delete(id: Int64) async throws {}
    func deleteBatch(ids: [Int64]) async throws {}
    func clearInbox() async throws {
        let snapshot: APIError? = queue.sync {
            _clearInboxCallCount += 1
            return _failOnClearInbox
        }
        if let err = snapshot { throw err }
    }
    func merge(_ request: MessageMergeRequest) async throws -> Message {
        Message(id: 1, content: request.title, mediaType: "COMPOSITE")
    }
    func createComposite(_ request: CompositeMessageRequest) async throws -> Message {
        Message(id: 1, content: request.title, mediaType: "COMPOSITE")
    }
}
