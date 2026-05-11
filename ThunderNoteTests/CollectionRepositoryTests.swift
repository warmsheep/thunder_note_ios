import XCTest
@testable import ThunderNote

final class CollectionRepositoryTests: XCTestCase {
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

    func test_list_decodesArray() async throws {
        let payload = """
        {"code":0,"message":"OK","data":[
          {"id":1,"name":"工作"},
          {"id":2,"name":"学习"}
        ],"timestamp":0}
        """
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/collections/list")
            XCTAssertEqual(request.httpMethod, "POST")
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }
        let repo = makeRepository()
        let collections = try await repo.list()
        XCTAssertEqual(collections.count, 2)
        XCTAssertEqual(collections[0].name, "工作")
    }

    func test_create_validatesEmptyName() async {
        let repo = makeRepository()
        do {
            _ = try await repo.create(name: "  ")
            XCTFail("应抛 nameEmpty")
        } catch let error as CollectionRepositoryError {
            XCTAssertEqual(error, .nameEmpty)
        } catch {
            XCTFail("错误类型不匹配：\(error)")
        }
    }

    func test_create_postsCorrectEndpoint() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/collections")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = """
            {"code":0,"message":"OK","data":{"id":99,"name":"工作"},"timestamp":0}
            """
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        let created = try await repo.create(name: "工作")
        XCTAssertEqual(created.id, 99)
        XCTAssertEqual(created.name, "工作")
    }

    func test_update_putsCorrectPath() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/collections/7")
            XCTAssertEqual(request.httpMethod, "PUT")
            let body = """
            {"code":0,"message":"OK","data":{"id":7,"name":"新名"},"timestamp":0}
            """
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        let updated = try await repo.update(id: 7, name: "新名")
        XCTAssertEqual(updated.id, 7)
    }

    func test_delete_callsDeleteEndpoint() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/collections/9")
            XCTAssertEqual(request.httpMethod, "DELETE")
            let body = #"{"code":0,"message":"OK","data":null,"timestamp":0}"#
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        try await repo.delete(id: 9)
    }

    private func makeRepository() -> CollectionRepositoryImpl {
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
        return CollectionRepositoryImpl(apiClient: client)
    }
}
