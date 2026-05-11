import XCTest
@testable import ThunderNote

final class CardEditorViewModelTests: XCTestCase {

    @MainActor
    func test_appendImage_addsDraft_untilLimit() throws {
        let vm = makeVM(target: .currentConversation(.flashNote(2)))
        let url = try writeTempFile(contents: "x", ext: "jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        for _ in 0..<CardEditorViewModel.maxItems {
            vm.appendImage(localURL: url)
        }
        XCTAssertEqual(vm.drafts.count, CardEditorViewModel.maxItems)
        XCTAssertFalse(vm.canAddMore)
        // 再加一个不应增长
        vm.appendImage(localURL: url)
        XCTAssertEqual(vm.drafts.count, CardEditorViewModel.maxItems)
        XCTAssertEqual(vm.transientMessage, "卡片最多 9 个媒体")
    }

    @MainActor
    func test_canSubmit_requiresTitleAndDrafts() throws {
        let vm = makeVM(target: .currentConversation(.flashNote(2)))
        XCTAssertFalse(vm.canSubmit)
        vm.title = "T"
        XCTAssertFalse(vm.canSubmit)
        let url = try writeTempFile(contents: "x", ext: "jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        vm.appendImage(localURL: url)
        XCTAssertTrue(vm.canSubmit)
        vm.title = "   "
        XCTAssertFalse(vm.canSubmit)
    }

    @MainActor
    func test_submit_emptyTitle_returnsFalseAndPostsTransientMessage() async throws {
        let vm = makeVM(target: .currentConversation(.flashNote(2)))
        let url = try writeTempFile(contents: "x", ext: "jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        vm.appendImage(localURL: url)
        let ok = await vm.submit()
        XCTAssertFalse(ok)
        XCTAssertEqual(vm.transientMessage, "请输入卡片标题")
    }

    @MainActor
    func test_submit_uploadsAllDrafts_andCallsCreateComposite() async throws {
        let stubFile = StubFileRepo()
        let stubMsg = StubCompositeMessageRepo()
        let vm = makeVM(
            target: .currentConversation(.flashNote(2)),
            fileRepo: stubFile,
            messageRepo: stubMsg
        )

        let imgURL = try writeTempFile(contents: "i", ext: "jpg")
        let docURL = try writeTempFile(contents: "doc body", ext: "txt")
        defer {
            try? FileManager.default.removeItem(at: imgURL)
            try? FileManager.default.removeItem(at: docURL)
        }
        vm.appendImage(localURL: imgURL)
        vm.appendFile(localURL: docURL)
        vm.title = "我的卡片"

        let ok = await vm.submit()
        XCTAssertTrue(ok)
        // 至少 2 次上传：图片本体 + 缩略图 / 文件本体
        XCTAssertGreaterThanOrEqual(stubFile.uploadCount, 2)
        XCTAssertEqual(stubMsg.compositeCalls.count, 1)
        let request = stubMsg.compositeCalls[0]
        XCTAssertEqual(request.title, "我的卡片")
        XCTAssertEqual(request.flashNoteId, 2)
        XCTAssertNil(request.receiverId)
        XCTAssertEqual(request.items.count, 2)
        XCTAssertTrue(request.items.contains { $0.type == "image" })
        XCTAssertTrue(request.items.contains { $0.type == "file" })
    }

    @MainActor
    func test_submit_inboxTarget_setsFlashNoteIdMinusOne() async throws {
        let stubFile = StubFileRepo()
        let stubMsg = StubCompositeMessageRepo()
        let vm = makeVM(
            target: .inbox,
            fileRepo: stubFile,
            messageRepo: stubMsg
        )
        let url = try writeTempFile(contents: "x", ext: "jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        vm.appendImage(localURL: url)
        vm.title = "to inbox"
        let ok = await vm.submit()
        XCTAssertTrue(ok)
        XCTAssertEqual(stubMsg.compositeCalls.first?.flashNoteId, FlashNote.inboxId)
    }

    // MARK: - Helpers

    @MainActor
    private func makeVM(
        target: CardEditorViewModel.Target,
        fileRepo: FileRepository = StubFileRepo(),
        messageRepo: MessageRepository = StubCompositeMessageRepo()
    ) -> CardEditorViewModel {
        let store = InMemoryTokenStore()
        let session = AuthSession(tokenStore: store)
        session.signIn(LoginResponse(
            accessToken: "A", refreshToken: "R", tokenType: "Bearer",
            expiresIn: 3600000,
            user: User(id: 1, username: "alice")
        ))
        return CardEditorViewModel(
            target: target,
            attachmentService: AttachmentSendingService(fileRepository: fileRepo),
            messageRepository: messageRepo,
            session: session
        )
    }

    private func writeTempFile(contents: String, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tn-cardvm-\(UUID().uuidString).\(ext)")
        try Data(contents.utf8).write(to: url)
        return url
    }
}

private final class StubFileRepo: FileRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.cardeditvm.file")
    private var _count: Int = 0
    var uploadCount: Int { queue.sync { _count } }

    func upload(
        fileURL: URL,
        mimeType: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> FileUploadResult {
        queue.sync { _count += 1 }
        return FileUploadResult(
            objectName: "1/\(UUID().uuidString)/\(fileURL.lastPathComponent)",
            originalFilename: fileURL.lastPathComponent
        )
    }

    func resolveDownloadURL(objectName: String?) -> URL? {
        guard let objectName else { return nil }
        return URL(string: "https://example.com/\(objectName)")
    }

    func download(objectName: String) async throws -> URL {
        URL(fileURLWithPath: "/tmp/stub-\(objectName.hashValue)")
    }
}

private final class StubCompositeMessageRepo: MessageRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.cardeditvm.msg")
    private var _calls: [CompositeMessageRequest] = []
    var compositeCalls: [CompositeMessageRequest] { queue.sync { _calls } }

    func listMessages(key: ConversationKey, page: Int, limit: Int) async throws -> PageData<Message> {
        PageData(records: [], total: 0, size: Int64(limit), current: 1, pages: 1)
    }
    func send(_ message: Message) async throws -> Message { message }
    func delete(id: Int64) async throws {}
    func deleteBatch(ids: [Int64]) async throws {}
    func clearInbox() async throws {}
    func merge(_ request: MessageMergeRequest) async throws -> Message {
        Message(id: 1, content: request.title, mediaType: "COMPOSITE")
    }
    func createComposite(_ request: CompositeMessageRequest) async throws -> Message {
        queue.sync { _calls.append(request) }
        return Message(id: 1, content: request.title, mediaType: "COMPOSITE")
    }
}
