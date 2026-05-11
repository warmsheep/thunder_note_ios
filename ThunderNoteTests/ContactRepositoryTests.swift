import XCTest
@testable import ThunderNote

final class ContactRepositoryTests: XCTestCase {
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

    func test_listContacts_decodesRelationStatus() async throws {
        let payload = """
        {"code":0,"message":"OK","data":[
          {"userId":1,"username":"a","relationStatus":"FRIEND"},
          {"userId":2,"username":"b","relationStatus":"PENDING_SENT","latestMessage":"hi"}
        ],"timestamp":0}
        """
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/users/contacts")
            XCTAssertEqual(request.httpMethod, "GET")
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }
        let repo = makeRepository()
        let contacts = try await repo.listContacts()
        XCTAssertEqual(contacts.count, 2)
        XCTAssertEqual(contacts[0].relationStatus, .friend)
        XCTAssertEqual(contacts[1].relationStatus, .pendingSent)
        XCTAssertEqual(contacts[1].latestMessage, "hi")
    }

    func test_listFriendRequests_decodes() async throws {
        let payload = """
        {"code":0,"message":"OK","data":[{"requestId":11,"userId":2,"username":"b"}],"timestamp":0}
        """
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/users/contacts/requests")
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }
        let repo = makeRepository()
        let requests = try await repo.listFriendRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].requestId, 11)
    }

    func test_friendRequestCount_decodesScalar() async throws {
        let payload = #"{"code":0,"message":"OK","data":3,"timestamp":0}"#
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/users/contacts/requests/count")
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }
        let repo = makeRepository()
        let count = try await repo.friendRequestCount()
        XCTAssertEqual(count, 3)
    }

    func test_sendFriendRequest_postsTargetUserId() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/users/contacts/request")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = #"{"code":0,"message":"OK","data":null,"timestamp":0}"#
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        try await repo.sendFriendRequest(targetUserId: 42)
    }

    func test_acceptAndReject_useCorrectPaths() async throws {
        // accept
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/users/contacts/request/accept")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = #"{"code":0,"message":"OK","data":null,"timestamp":0}"#
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        try await repo.acceptFriendRequest(requestId: 11)

        // reject
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/users/contacts/request/reject")
            let body = #"{"code":0,"message":"OK","data":null,"timestamp":0}"#
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        try await repo.rejectFriendRequest(requestId: 11)
    }

    func test_removeContact_deletesByUserId() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/users/contacts/123")
            XCTAssertEqual(request.httpMethod, "DELETE")
            let body = #"{"code":0,"message":"OK","data":null,"timestamp":0}"#
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        try await repo.removeContact(userId: 123)
    }

    func test_search_appendsKeywordQuery() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/users/contacts/search")
            XCTAssertTrue(request.url?.query?.contains("keyword=alice") == true)
            let body = """
            {"code":0,"message":"OK","data":[{"userId":2,"username":"alice","relationStatus":"NONE"}],"timestamp":0}
            """
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        let results = try await repo.search(keyword: "alice")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].relationStatus, .none)
    }

    func test_search_emptyKeywordSkipsRequest() async throws {
        MockURLProtocol.handler = { _ in
            XCTFail("空 keyword 不应触发请求")
            return (HTTPURLResponse.make(url: URL(string: "https://example.com")!, status: 200), Data())
        }
        let repo = makeRepository()
        let results = try await repo.search(keyword: "   ")
        XCTAssertEqual(results.count, 0)
    }

    private func makeRepository() -> ContactRepositoryImpl {
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
        return ContactRepositoryImpl(apiClient: client)
    }
}
