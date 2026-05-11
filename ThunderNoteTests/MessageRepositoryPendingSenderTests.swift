import XCTest
@testable import ThunderNote

/// D2-I7-05 Step 2B：MessageRepositoryPendingSender 单测。
final class MessageRepositoryPendingSenderTests: XCTestCase {

    // MARK: - PendingMessage → Message 映射

    func test_message_fromTextPending_buildsExpectedMessage() throws {
        let pending = PendingMessageLocal(
            username: "alice",
            conversationKey: 7,
            flashNoteId: 7,
            peerUserId: nil,
            clientRequestId: "req-1",
            mediaType: "TEXT",
            content: "hello",
            status: .queued
        )
        let message = try MessageRepositoryPendingSender.message(from: pending)
        XCTAssertEqual(message.content, "hello")
        XCTAssertEqual(message.clientRequestId, "req-1")
        XCTAssertEqual(message.flashNoteId, 7)
        XCTAssertEqual(message.mediaType, "TEXT")
        XCTAssertNil(message.mediaUrl)
        XCTAssertNil(message.senderId) // 后端按 token 决定
    }

    func test_message_fromTextPending_emptyContent_throws() {
        let pending = PendingMessageLocal(
            username: "alice", conversationKey: 7,
            clientRequestId: "req", mediaType: "TEXT", content: "",
            status: .queued
        )
        XCTAssertThrowsError(try MessageRepositoryPendingSender.message(from: pending))
    }

    func test_message_fromMediaPending_withoutRemoteUrl_throws() {
        let pending = PendingMessageLocal(
            username: "alice", conversationKey: 7,
            mediaType: "IMAGE", content: nil,
            remoteUrl: nil, // 未上传
            status: .queued
        )
        XCTAssertThrowsError(try MessageRepositoryPendingSender.message(from: pending))
    }

    func test_message_fromMediaPending_withRemoteUrl_buildsMessage() throws {
        let pending = PendingMessageLocal(
            username: "alice", conversationKey: 7,
            peerUserId: 42,
            clientRequestId: "req-2",
            mediaType: "IMAGE", content: nil,
            remoteUrl: "https://cdn.example.com/img.jpg",
            fileName: "img.jpg", fileSize: 1024,
            mediaDuration: nil,
            thumbnailUrl: "https://cdn.example.com/img-thumb.jpg",
            status: .queued
        )
        let message = try MessageRepositoryPendingSender.message(from: pending)
        XCTAssertEqual(message.mediaType, "IMAGE")
        XCTAssertEqual(message.mediaUrl, "https://cdn.example.com/img.jpg")
        XCTAssertEqual(message.thumbnailUrl, "https://cdn.example.com/img-thumb.jpg")
        XCTAssertEqual(message.fileName, "img.jpg")
        XCTAssertEqual(message.fileSize, 1024)
        XCTAssertEqual(message.receiverId, 42)
        XCTAssertEqual(message.clientRequestId, "req-2")
    }

    // MARK: - send 走 MessageRepository

    func test_send_dispatchesToMessageRepository_andReturnsServerId() async throws {
        let repo = MockMessageRepository()
        repo.sendBehavior = .return(Message(id: 99, content: "hi", clientRequestId: "req"))
        let sender = MessageRepositoryPendingSender(messageRepository: repo)
        let pending = PendingMessageLocal(
            username: "alice", conversationKey: 7, flashNoteId: 7,
            clientRequestId: "req", mediaType: "TEXT", content: "hi",
            status: .queued
        )
        let id = try await sender.send(pending)
        XCTAssertEqual(id, 99)
        XCTAssertEqual(repo.sendCount, 1)
        XCTAssertEqual(repo.lastSent?.clientRequestId, "req")
    }

    func test_send_propagatesRepositoryError() async {
        let repo = MockMessageRepository()
        repo.sendBehavior = .throw(APIError.business(code: 500, message: "boom"))
        let sender = MessageRepositoryPendingSender(messageRepository: repo)
        let pending = PendingMessageLocal(
            username: "alice", conversationKey: 7,
            clientRequestId: "req", mediaType: "TEXT", content: "x",
            status: .queued
        )
        do {
            _ = try await sender.send(pending)
            XCTFail("expected throw")
        } catch let err as APIError {
            XCTAssertEqual(err.displayMessage, "boom")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

/// 测试用 MessageRepository mock。仅实现协议必需方法。
private final class MockMessageRepository: MessageRepository, @unchecked Sendable {
    enum SendBehavior {
        case `return`(Message)
        case `throw`(Error)
    }
    private let queue = DispatchQueue(label: "tn.tests.msgrepo")
    private var _sendCount = 0
    private var _lastSent: Message?
    var sendBehavior: SendBehavior = .return(Message())

    var sendCount: Int { queue.sync { _sendCount } }
    var lastSent: Message? { queue.sync { _lastSent } }

    func listMessages(key: ConversationKey, page: Int, limit: Int) async throws -> PageData<Message> {
        // 测试不会经过这条路径；为了占位返回一个用 JSON decode 出来的空 PageData。
        let json = #"{"records":[],"total":0,"size":0,"current":\#(page),"pages":0}"#
        return try JSONDecoder().decode(PageData<Message>.self, from: Data(json.utf8))
    }
    func send(_ message: Message) async throws -> Message {
        queue.sync {
            _sendCount += 1
            _lastSent = message
        }
        switch sendBehavior {
        case .return(let m):
            return m
        case .throw(let err):
            throw err
        }
    }
    func delete(id: Int64) async throws {}
    func deleteBatch(ids: [Int64]) async throws {}
    func clearInbox() async throws {}
    func merge(_ request: MessageMergeRequest) async throws -> Message { Message() }
    func createComposite(_ request: CompositeMessageRequest) async throws -> Message { Message() }
    func countMessages() async throws -> Int64 { 0 }
}
