import XCTest
@testable import ThunderNote

final class FlashNoteSearchViewModelTests: XCTestCase {

    /// 先有结果再清空：输入空白触发立即清空，不再发请求。
    @MainActor
    func test_onQueryChanged_blank_clearsImmediatelyAndDoesNotCallRepo() async {
        let repo = StubSearchRepository()
        repo.response = FlashNoteSearchResponse(
            noteNameMatched: [makeResult(id: 1, title: "x")],
            messageContentMatched: []
        )
        let vm = FlashNoteSearchViewModel(repository: repo, debounce: .milliseconds(10))

        vm.onQueryChanged("x")
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(vm.noteNameMatched.isEmpty)
        let firstCallCount = repo.callCount

        vm.onQueryChanged("   ")

        XCTAssertEqual(vm.activeQuery, "")
        XCTAssertTrue(vm.noteNameMatched.isEmpty)
        XCTAssertTrue(vm.messageContentMatched.isEmpty)
        XCTAssertEqual(repo.callCount, firstCallCount, "空查询不再发请求")
    }

    /// 输入非空 → 等待防抖后调用 repo，结果落到对应字段。
    @MainActor
    func test_onQueryChanged_nonBlank_callsRepoAfterDebounce() async {
        let repo = StubSearchRepository()
        repo.response = FlashNoteSearchResponse(
            noteNameMatched: [makeResult(id: 1, title: "旅行")],
            messageContentMatched: [
                FlashNoteSearchResult(
                    flashNote: FlashNote(id: 2, title: "工作"),
                    matchedMessages: [
                        MatchedMessageInfo(messageId: 100, snippet: "命中片段", contextMessages: [])
                    ],
                    noteMatched: false
                )
            ]
        )
        let vm = FlashNoteSearchViewModel(repository: repo, debounce: .milliseconds(10))

        vm.onQueryChanged("旅行")
        // 等防抖完成 + 网络回包。
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(repo.lastQuery, "旅行")
        XCTAssertEqual(vm.noteNameMatched.count, 1)
        XCTAssertEqual(vm.messageContentMatched.first?.matchedMessages.first?.messageId, 100)
        XCTAssertFalse(vm.isLoading)
    }

    /// 输入空白后 trim 也是空 → 不发请求。
    @MainActor
    func test_onQueryChanged_trimmedEmpty_noRepoCall() async {
        let repo = StubSearchRepository()
        let vm = FlashNoteSearchViewModel(repository: repo, debounce: .milliseconds(10))

        vm.onQueryChanged("\n  \t")
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(repo.callCount, 0)
    }

    /// 防抖期间连续输入 → 仅最后一次走网络。
    @MainActor
    func test_onQueryChanged_debouncesRapidInput() async {
        let repo = StubSearchRepository()
        repo.response = FlashNoteSearchResponse(noteNameMatched: [], messageContentMatched: [])
        let vm = FlashNoteSearchViewModel(repository: repo, debounce: .milliseconds(50))

        vm.onQueryChanged("a")
        vm.onQueryChanged("ab")
        vm.onQueryChanged("abc")
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(repo.callCount, 1)
        XCTAssertEqual(repo.lastQuery, "abc")
    }

    /// repo 失败 → transientMessage 非空，loading 复位。
    @MainActor
    func test_repoFailure_setsTransientMessage() async {
        let repo = StubSearchRepository()
        repo.error = APIError.business(code: 50000, message: "服务器错误")
        let vm = FlashNoteSearchViewModel(repository: repo, debounce: .milliseconds(10))

        vm.onQueryChanged("hi")
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(vm.transientMessage)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.activeQuery, "hi")
    }

    /// onDeactivate → 取消 in-flight、清空状态。
    @MainActor
    func test_onDeactivate_clearsState() async {
        let repo = StubSearchRepository()
        repo.response = FlashNoteSearchResponse(
            noteNameMatched: [makeResult(id: 1, title: "x")],
            messageContentMatched: []
        )
        let vm = FlashNoteSearchViewModel(repository: repo, debounce: .milliseconds(10))
        vm.query = "x"
        vm.onQueryChanged("x")
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(vm.noteNameMatched.isEmpty)

        vm.onDeactivate()

        XCTAssertEqual(vm.query, "")
        XCTAssertEqual(vm.activeQuery, "")
        XCTAssertTrue(vm.noteNameMatched.isEmpty)
        XCTAssertTrue(vm.messageContentMatched.isEmpty)
    }

    /// submitNow → 跳过防抖立即触发；空查询不发。
    @MainActor
    func test_submitNow_triggersImmediately() async {
        let repo = StubSearchRepository()
        repo.response = FlashNoteSearchResponse(noteNameMatched: [], messageContentMatched: [])
        let vm = FlashNoteSearchViewModel(repository: repo, debounce: .milliseconds(500))
        vm.query = "fast"

        await vm.submitNow()

        XCTAssertEqual(repo.callCount, 1)
        XCTAssertEqual(vm.activeQuery, "fast")
    }

    /// isEmptyResult：搜索激活 + 已结束 + 两段都空才为 true。
    @MainActor
    func test_isEmptyResult_onlyTrueAfterCompletedSearch() async {
        let repo = StubSearchRepository()
        repo.response = FlashNoteSearchResponse(noteNameMatched: [], messageContentMatched: [])
        let vm = FlashNoteSearchViewModel(repository: repo, debounce: .milliseconds(10))

        XCTAssertFalse(vm.isEmptyResult) // 未激活
        vm.onQueryChanged("zz")
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(vm.isEmptyResult)
    }

    // MARK: - Helpers

    private func makeResult(id: Int64, title: String) -> FlashNoteSearchResult {
        FlashNoteSearchResult(
            flashNote: FlashNote(id: id, title: title),
            matchedMessages: [],
            noteMatched: true
        )
    }
}

private final class StubSearchRepository: FlashNoteRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.flashnote.searchstub")
    private var _callCount: Int = 0
    private var _lastQuery: String?

    var response: FlashNoteSearchResponse = FlashNoteSearchResponse(
        noteNameMatched: [],
        messageContentMatched: []
    )
    var error: APIError? = nil

    var callCount: Int { queue.sync { _callCount } }
    var lastQuery: String? { queue.sync { _lastQuery } }

    func list() async throws -> [FlashNote] { [] }
    func create(title: String, icon: String?, tags: String?) async throws -> FlashNote {
        FlashNote(id: 1, title: title)
    }
    func update(id: Int64, title: String, icon: String?, tags: String?) async throws -> FlashNote {
        FlashNote(id: id, title: title)
    }
    func setPinned(id: Int64, value: Bool) async throws {}
    func setHidden(id: Int64, value: Bool) async throws {}
    func delete(id: Int64) async throws {}

    func search(query: String) async throws -> FlashNoteSearchResponse {
        queue.sync {
            _callCount += 1
            _lastQuery = query
        }
        if let error { throw error }
        return response
    }
}
