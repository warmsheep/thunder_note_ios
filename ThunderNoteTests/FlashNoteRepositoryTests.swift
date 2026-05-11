import XCTest
@testable import ThunderNote

final class FlashNoteRepositoryTests: XCTestCase {
    private var session: URLSession!
    private let baseURL = URL(string: "https://example.com/")!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = MockURLProtocol.makeSession()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    func test_list_decodesNotes() async throws {
        let payload = """
        {"code":0,"message":"OK","data":[
          {"id":-1,"title":"收集箱","inbox":true,"pinned":true},
          {"id":1,"title":"工作","icon":"💼","pinned":true,"updatedAt":"2026-05-01T10:00:00"},
          {"id":2,"title":"灵感","icon":"💡","updatedAt":"2026-05-02T10:00:00"}
        ],"timestamp":0}
        """
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/flash-notes/list")
            XCTAssertEqual(request.httpMethod, "POST")
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }
        let repo = makeRepository()
        let notes = try await repo.list()
        XCTAssertEqual(notes.count, 3)
        XCTAssertEqual(notes[0].id, -1)
        XCTAssertTrue(notes[0].isInbox)
        XCTAssertEqual(notes[1].title, "工作")
    }

    func test_create_validatesEmptyTitle() async {
        let repo = makeRepository()
        do {
            _ = try await repo.create(title: "   ", icon: "💼", tags: nil)
            XCTFail("应抛 titleEmpty")
        } catch let error as FlashNoteRepositoryError {
            XCTAssertEqual(error, .titleEmpty)
        } catch {
            XCTFail("错误类型不匹配：\(error)")
        }
    }

    func test_update_rejectsInboxId() async {
        let repo = makeRepository()
        do {
            _ = try await repo.update(id: FlashNote.inboxId, title: "x", icon: nil, tags: nil)
            XCTFail("应抛 inboxImmutable")
        } catch let error as FlashNoteRepositoryError {
            XCTAssertEqual(error, .inboxImmutable)
        } catch {
            XCTFail("错误类型不匹配：\(error)")
        }
    }

    func test_delete_rejectsInboxId() async {
        let repo = makeRepository()
        do {
            try await repo.delete(id: FlashNote.inboxId)
            XCTFail("应抛 inboxImmutable")
        } catch let error as FlashNoteRepositoryError {
            XCTAssertEqual(error, .inboxImmutable)
        } catch {
            XCTFail("错误类型不匹配：\(error)")
        }
    }

    func test_setPinned_rejectsInboxUnpin() async {
        let repo = makeRepository()
        do {
            try await repo.setPinned(id: FlashNote.inboxId, value: false)
            XCTFail("应抛 inboxImmutable")
        } catch let error as FlashNoteRepositoryError {
            XCTAssertEqual(error, .inboxImmutable)
        } catch {
            XCTFail("错误类型不匹配：\(error)")
        }
    }

    func test_setPinned_passesValueAsQuery() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/flash-notes/123/pin")
            XCTAssertTrue(request.url?.query?.contains("value=true") == true)
            let body = #"{"code":0,"message":"OK","data":null,"timestamp":0}"#
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        try await repo.setPinned(id: 123, value: true)
    }

    func test_setHidden_rejectsInbox() async {
        let repo = makeRepository()
        do {
            try await repo.setHidden(id: FlashNote.inboxId, value: true)
            XCTFail("应抛 inboxImmutable")
        } catch let error as FlashNoteRepositoryError {
            XCTAssertEqual(error, .inboxImmutable)
        } catch {
            XCTFail("错误类型不匹配：\(error)")
        }
    }

    func test_create_postsToCreateEndpointWithBody() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/flash-notes")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = """
            {"code":0,"message":"OK","data":{"id":99,"title":"新闪记","icon":"💡","tags":"学习"},"timestamp":0}
            """
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        let note = try await repo.create(title: "新闪记", icon: "💡", tags: "学习")
        XCTAssertEqual(note.id, 99)
        XCTAssertEqual(note.icon, "💡")
        XCTAssertEqual(note.tags, "学习")
    }

    func test_delete_callsDeleteEndpoint() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/flash-notes/77")
            XCTAssertEqual(request.httpMethod, "DELETE")
            let body = #"{"code":0,"message":"OK","data":null,"timestamp":0}"#
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        try await repo.delete(id: 77)
    }

    private func makeRepository() -> FlashNoteRepositoryImpl {
        let serverConfig = StaticServerConfig(baseURL: baseURL)
        let tokenStore = InMemoryTokenStore()
        tokenStore.save(loginResponse: LoginResponse(
            accessToken: "A",
            refreshToken: "R",
            tokenType: "Bearer",
            expiresIn: 3600000,
            user: User(id: 1, username: "alice")
        ))
        let accessor = DefaultTokenAccessor(tokenStore: tokenStore)
        let client = APIClient(
            session: session,
            serverConfigStore: serverConfig,
            tokenAccessor: accessor,
            userAgent: "ThunderNoteTest/0.0",
            acceptLanguage: "zh-Hans"
        )
        return FlashNoteRepositoryImpl(apiClient: client)
    }
}
