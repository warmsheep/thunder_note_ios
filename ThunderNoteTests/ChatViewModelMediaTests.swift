import XCTest
@testable import ThunderNote

final class ChatViewModelMediaTests: XCTestCase {
    @MainActor
    func test_scrollToMessageId_findsTargetInLoadedPage() async {
        let target = Message(id: 42, content: "hi", createdAt: "2026-05-11T10:00:00", mediaType: "TEXT")
        let other = Message(id: 7, content: "x", createdAt: "2026-05-11T09:00:00", mediaType: "TEXT")
        let repo = StubMediaRepo(records: [target, other])
        let vm = ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "x", targetMessageId: 42),
            messageRepository: repo,
            session: makeSession(),
            draftStore: DraftStore()
        )

        await vm.loadInitial()

        XCTAssertEqual(vm.scrollTargetMessageId, 42)
        XCTAssertEqual(vm.highlightedMessageId, 42)
    }

    @MainActor
    func test_scrollToMessageId_missingShowsTransientMessage() async {
        let repo = StubMediaRepo(records: [
            Message(id: 5, content: "x", createdAt: "2026-05-11T10:00:00", mediaType: "TEXT")
        ])
        let vm = ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "x", targetMessageId: 9999),
            messageRepository: repo,
            session: makeSession(),
            draftStore: DraftStore()
        )

        await vm.loadInitial()

        XCTAssertNil(vm.scrollTargetMessageId)
        XCTAssertEqual(vm.transientMessage, "未找到该消息（可能已删除或过旧）")
    }

    @MainActor
    func test_didConsumeScrollTarget_clearsScrollTarget() async {
        let target = Message(id: 42, content: "hi", createdAt: "2026-05-11T10:00:00", mediaType: "TEXT")
        let repo = StubMediaRepo(records: [target])
        let vm = ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "x", targetMessageId: 42),
            messageRepository: repo,
            session: makeSession(),
            draftStore: DraftStore()
        )

        await vm.loadInitial()
        XCTAssertEqual(vm.scrollTargetMessageId, 42)
        vm.didConsumeScrollTarget()
        XCTAssertNil(vm.scrollTargetMessageId)
        // 高亮还在（1.5s 内）
        XCTAssertEqual(vm.highlightedMessageId, 42)
    }

    @MainActor
    func test_sendImage_optimisticPendingThenSent() async {
        let stubFile = StubFileRepo()
        let attachmentService = AttachmentSendingService(fileRepository: stubFile)
        let stubMessage = StubMediaRepo(records: [], echoOnSend: true)
        let vm = ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "x"),
            messageRepository: stubMessage,
            session: makeSession(),
            draftStore: DraftStore(),
            attachmentService: attachmentService
        )
        await vm.loadInitial()

        // 准备一个真实的本地图片文件（用 1x1 PNG bytes）
        let url = try! makeTinyImage()
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.sendImage(localURL: url)

        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.last?.status, .sent)
        XCTAssertEqual(vm.items.last?.message.resolvedMediaType, .image)
        XCTAssertEqual(stubFile.uploadCalls.count, 2, "图片应上传一份原文件 + 一份缩略图")
    }

    @MainActor
    func test_sendFile_optimisticPendingThenSent() async {
        let stubFile = StubFileRepo()
        let attachmentService = AttachmentSendingService(fileRepository: stubFile)
        let stubMessage = StubMediaRepo(records: [], echoOnSend: true)
        let vm = ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "x"),
            messageRepository: stubMessage,
            session: makeSession(),
            draftStore: DraftStore(),
            attachmentService: attachmentService
        )
        await vm.loadInitial()

        let url = try! writeTempFile(contents: "report contents", ext: "txt")
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.sendFile(localURL: url)

        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.last?.status, .sent)
        XCTAssertEqual(vm.items.last?.message.resolvedMediaType, .file)
        XCTAssertEqual(vm.items.last?.message.fileName, url.lastPathComponent)
    }

    @MainActor
    func test_sendImage_uploadFailureMarksItemFailed() async {
        let stubFile = StubFileRepo(failOnUpload: true)
        let attachmentService = AttachmentSendingService(fileRepository: stubFile)
        let stubMessage = StubMediaRepo(records: [], echoOnSend: true)
        let vm = ChatViewModel(
            configuration: .init(key: .flashNote(2), title: "x"),
            messageRepository: stubMessage,
            session: makeSession(),
            draftStore: DraftStore(),
            attachmentService: attachmentService
        )
        await vm.loadInitial()

        let url = try! makeTinyImage()
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.sendImage(localURL: url)

        XCTAssertEqual(vm.items.count, 1)
        if case .failed = vm.items.last?.status {
            XCTAssertTrue(true)
        } else {
            XCTFail("应进入 failed 状态")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func makeSession() -> AuthSession {
        let store = InMemoryTokenStore()
        let session = AuthSession(tokenStore: store)
        session.signIn(LoginResponse(
            accessToken: "A", refreshToken: "R", tokenType: "Bearer",
            expiresIn: 3600000,
            user: User(id: 1, username: "alice")
        ))
        return session
    }

    private func makeTinyImage() throws -> URL {
        // 1x1 transparent PNG（base64 解码后写到 tmp）
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        let data = Data(base64Encoded: base64)!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tn-test-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    private func writeTempFile(contents: String, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tn-test-\(UUID().uuidString).\(ext)")
        try Data(contents.utf8).write(to: url)
        return url
    }
}

// MARK: - Stubs

private final class StubMediaRepo: MessageRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.media.msg")
    private var _records: [Message]
    private let echoOnSend: Bool
    private var _serverIdSeed: Int64 = 1000

    init(records: [Message], echoOnSend: Bool = false) {
        self._records = records
        self.echoOnSend = echoOnSend
    }

    func listMessages(key: ConversationKey, page: Int, limit: Int) async throws -> PageData<Message> {
        let snap = queue.sync { _records }
        return PageData(records: snap, total: Int64(snap.count), size: Int64(limit), current: 1, pages: 1)
    }

    func send(_ message: Message) async throws -> Message {
        if echoOnSend {
            var copy = message
            queue.sync {
                _serverIdSeed += 1
                copy.id = _serverIdSeed
            }
            return copy
        }
        return message
    }

    func delete(id: Int64) async throws {}
    func deleteBatch(ids: [Int64]) async throws {}
    func clearInbox() async throws {}
}

private final class StubFileRepo: FileRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.media.file")
    private var _uploadCalls: [URL] = []
    private let failOnUpload: Bool

    init(failOnUpload: Bool = false) { self.failOnUpload = failOnUpload }

    var uploadCalls: [URL] { queue.sync { _uploadCalls } }

    func upload(
        fileURL: URL,
        mimeType: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> FileUploadResult {
        if failOnUpload {
            throw APIError.business(code: 50000, message: "upload boom")
        }
        queue.sync { _uploadCalls.append(fileURL) }
        return FileUploadResult(
            objectName: "stub/\(UUID().uuidString)/\(fileURL.lastPathComponent)",
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
