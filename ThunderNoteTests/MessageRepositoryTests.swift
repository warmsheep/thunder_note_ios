import XCTest
@testable import ThunderNote

final class MessageRepositoryTests: XCTestCase {
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

    func test_listMessages_decodesPageData() async throws {
        let payload = """
        {"code":0,"message":"OK","data":{
          "records":[
            {"id":1,"senderId":1,"receiverId":1,"content":"hi","flashNoteId":2,"createdAt":"2026-05-11T10:00:00","mediaType":"TEXT"},
            {"id":2,"senderId":1,"receiverId":1,"content":"hello","flashNoteId":2,"createdAt":"2026-05-11T10:01:00","mediaType":"TEXT"}
          ],
          "total":2,"size":20,"current":1,"pages":1
        },"timestamp":0}
        """
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/messages/list")
            XCTAssertEqual(request.httpMethod, "POST")
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }
        let repo = makeRepository()
        let page = try await repo.listMessages(key: .flashNote(2), page: 1, limit: 20)
        XCTAssertEqual(page.safeRecords.count, 2)
        XCTAssertEqual(page.safeRecords[0].content, "hi")
        XCTAssertFalse(page.hasMore)
    }

    func test_send_postsMessageBodyAndDecodes() async throws {
        let payload = """
        {"code":0,"message":"OK","data":{"id":42,"senderId":1,"receiverId":1,"content":"hi","clientRequestId":"abc","mediaType":"TEXT","createdAt":"2026-05-11T10:00:00"},"timestamp":0}
        """
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/messages")
            XCTAssertEqual(request.httpMethod, "POST")
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }
        let repo = makeRepository()
        let outgoing = Message(content: "hi", clientRequestId: "abc", mediaType: "TEXT")
        let confirmed = try await repo.send(outgoing)
        XCTAssertEqual(confirmed.id, 42)
        XCTAssertEqual(confirmed.clientRequestId, "abc")
    }

    func test_delete_callsDeleteEndpoint() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/messages/9")
            XCTAssertEqual(request.httpMethod, "DELETE")
            let body = #"{"code":0,"message":"OK","data":null,"timestamp":0}"#
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        try await repo.delete(id: 9)
    }

    func test_clearInbox_callsClearEndpoint() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/messages/clear-inbox")
            XCTAssertEqual(request.httpMethod, "DELETE")
            let body = #"{"code":0,"message":"OK","data":null,"timestamp":0}"#
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        try await repo.clearInbox()
    }

    func test_deleteBatch_postsIdsBody() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/messages/delete-batch")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = #"{"code":0,"message":"OK","data":null,"timestamp":0}"#
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        try await repo.deleteBatch(ids: [1, 2, 3])
    }

    func test_deleteBatch_emptyIdsIsNoop() async throws {
        MockURLProtocol.handler = { _ in
            XCTFail("空 ids 不应触发请求")
            return (HTTPURLResponse.make(url: URL(string: "https://example.com")!, status: 200), Data())
        }
        let repo = makeRepository()
        try await repo.deleteBatch(ids: [])
    }

    func test_merge_postsMergeBodyAndDecodes() async throws {
        let payload = """
        {"code":0,"message":"OK","data":{
          "id":777,"senderId":1,"receiverId":1,"flashNoteId":2,"mediaType":"COMPOSITE","content":"标题",
          "payload":{
            "cardType":"MESSAGE_COLLECTION","title":"标题","summary":"hi 等2条消息",
            "items":[
              {"originalMsgId":1,"type":"TEXT","content":"hi","senderId":1,"role":"user"},
              {"originalMsgId":2,"type":"TEXT","content":"hello","senderId":1,"role":"user"}
            ]
          },
          "createdAt":"2026-05-11T10:02:00"
        },"timestamp":0}
        """
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/messages/merge")
            XCTAssertEqual(request.httpMethod, "POST")
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }
        let repo = makeRepository()
        let result = try await repo.merge(MessageMergeRequest(
            title: "标题",
            messageIds: [1, 2],
            flashNoteId: 2,
            receiverId: nil
        ))
        XCTAssertEqual(result.id, 777)
        XCTAssertEqual(result.payload?.cardType, "MESSAGE_COLLECTION")
        XCTAssertEqual(result.payload?.items?.count, 2)
        XCTAssertEqual(result.payload?.items?.first?.content, "hi")
    }

    func test_createComposite_postsCompositeBodyAndDecodes() async throws {
        let payload = """
        {"code":0,"message":"OK","data":{
          "id":888,"senderId":1,"receiverId":1,"flashNoteId":2,"mediaType":"COMPOSITE","content":"卡片",
          "payload":{
            "cardType":"COMPOSITE_MEDIA","title":"卡片",
            "items":[
              {"type":"image","url":"1/abc.jpg","thumbnailUrl":"1/abc.thumb.jpg"}
            ]
          },
          "createdAt":"2026-05-11T10:03:00"
        },"timestamp":0}
        """
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/messages/composite")
            XCTAssertEqual(request.httpMethod, "POST")
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }
        let repo = makeRepository()
        let req = CompositeMessageRequest(
            title: "卡片",
            content: nil,
            flashNoteId: 2,
            receiverId: nil,
            items: [
                .init(type: "image", mediaUrl: "1/abc.jpg", thumbnailUrl: "1/abc.thumb.jpg")
            ]
        )
        let result = try await repo.createComposite(req)
        XCTAssertEqual(result.id, 888)
        XCTAssertEqual(result.payload?.items?.first?.mediaUrl, "1/abc.jpg")
        XCTAssertEqual(result.payload?.items?.first?.resolvedMediaType, .image)
    }

    private func makeRepository() -> MessageRepositoryImpl {
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
        return MessageRepositoryImpl(apiClient: client)
    }
}
