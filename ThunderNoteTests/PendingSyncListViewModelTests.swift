import XCTest
@testable import ThunderNote

/// D2-I7-09 待同步列表 ViewModel 单测。
final class PendingSyncListViewModelTests: XCTestCase {

    private var dbURL: URL!
    private var database: TNDatabase!
    private var dao: SQLitePendingMessageDao!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tn-pendinglist-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("list.sqlite3")
        database = try! TNDatabase(fileURL: dbURL)
        dao = SQLitePendingMessageDao(database: database)
    }

    override func tearDown() {
        dao = nil
        database = nil
        if let url = dbURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        super.tearDown()
    }

    @MainActor
    func test_refresh_loadsItemsForCurrentUserOrdered() throws {
        _ = try dao.insert(PendingMessageLocal(
            username: "alice", conversationKey: 7, content: "a",
            status: .queued, createdAt: 100
        ))
        _ = try dao.insert(PendingMessageLocal(
            username: "alice", conversationKey: 7, content: "b",
            status: .queued, createdAt: 200
        ))
        _ = try dao.insert(PendingMessageLocal(
            username: "bob", conversationKey: 7, content: "bob-row",
            status: .queued, createdAt: 50
        ))
        let vm = PendingSyncListViewModel(dao: dao, usernameProvider: { "alice" })
        vm.refresh()
        XCTAssertEqual(vm.items.map { $0.content }, ["a", "b"])
    }

    @MainActor
    func test_refresh_emptyWhenUsernameNil() throws {
        _ = try dao.insert(PendingMessageLocal(
            username: "alice", conversationKey: 7, content: "x",
            status: .queued
        ))
        let vm = PendingSyncListViewModel(dao: dao, usernameProvider: { nil })
        vm.refresh()
        XCTAssertTrue(vm.items.isEmpty)
    }

    func test_displayContent_prefersContentThenFileNameThenMediaLabel() {
        XCTAssertEqual(
            PendingSyncListViewModel.displayContent(
                .stub(content: "hello", fileName: "img.jpg", mediaType: "IMAGE")
            ),
            "hello"
        )
        XCTAssertEqual(
            PendingSyncListViewModel.displayContent(
                .stub(content: "", fileName: "img.jpg", mediaType: "IMAGE")
            ),
            "img.jpg"
        )
        XCTAssertEqual(
            PendingSyncListViewModel.displayContent(
                .stub(content: nil, fileName: nil, mediaType: "IMAGE")
            ),
            "[图片]"
        )
        XCTAssertEqual(
            PendingSyncListViewModel.displayContent(
                .stub(content: nil, fileName: nil, mediaType: "VIDEO")
            ),
            "[视频]"
        )
        XCTAssertEqual(
            PendingSyncListViewModel.displayContent(
                .stub(content: nil, fileName: nil, mediaType: "TEXT")
            ),
            "[文本]"
        )
        XCTAssertEqual(
            PendingSyncListViewModel.displayContent(
                .stub(content: nil, fileName: nil, mediaType: "STICKER")
            ),
            "[媒体]"
        )
    }

    func test_displayTarget_handlesPeerInboxFlashNoteUnknown() {
        XCTAssertEqual(
            PendingSyncListViewModel.displayTarget(.stub(peerUserId: 99)),
            "联系人 #99"
        )
        XCTAssertEqual(
            PendingSyncListViewModel.displayTarget(.stub(flashNoteId: -1)),
            "收集箱"
        )
        XCTAssertEqual(
            PendingSyncListViewModel.displayTarget(.stub(flashNoteId: 7)),
            "闪记 #7"
        )
        XCTAssertEqual(
            PendingSyncListViewModel.displayTarget(.stub()),
            "未知会话"
        )
    }

    func test_displayStatus_coversAllStates() {
        XCTAssertEqual(PendingSyncListViewModel.displayStatus(.queued), "排队中")
        XCTAssertEqual(PendingSyncListViewModel.displayStatus(.uploading), "上传中")
        XCTAssertEqual(PendingSyncListViewModel.displayStatus(.failed), "失败")
        XCTAssertEqual(PendingSyncListViewModel.displayStatus(.sending), "发送中")
        XCTAssertEqual(PendingSyncListViewModel.displayStatus(.sent), "已发送")
    }
}

private extension PendingMessageLocal {
    static func stub(
        content: String? = nil,
        fileName: String? = nil,
        mediaType: String? = nil,
        flashNoteId: Int64? = nil,
        peerUserId: Int64? = nil
    ) -> PendingMessageLocal {
        PendingMessageLocal(
            username: "alice",
            conversationKey: 7,
            flashNoteId: flashNoteId,
            peerUserId: peerUserId,
            clientRequestId: nil,
            mediaType: mediaType,
            content: content,
            fileName: fileName,
            status: .queued
        )
    }
}
