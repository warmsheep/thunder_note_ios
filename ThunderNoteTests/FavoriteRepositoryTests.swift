import XCTest
@testable import ThunderNote

final class FavoriteRepositoryTests: XCTestCase {
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

    func test_list_decodesFavoritesAndIcon() async throws {
        let payload = """
        {"code":0,"message":"OK","data":[
          {"id":1,"messageId":10,"flashNoteId":-1,"flashNoteTitle":"收集箱","flashNoteIcon":"📥","content":"hi","mediaType":"TEXT","favoritedAt":"2026-05-11T10:00:00"},
          {"id":2,"messageId":11,"flashNoteId":7,"flashNoteTitle":"工作","mediaType":"IMAGE","favoritedAt":"2026-05-11T11:00:00"}
        ],"timestamp":0}
        """
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/favorites/list")
            XCTAssertEqual(request.httpMethod, "POST")
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }
        let repo = makeRepository()
        let favorites = try await repo.list()
        XCTAssertEqual(favorites.count, 2)
        XCTAssertEqual(favorites[0].flashNoteIcon, "📥")
        XCTAssertEqual(favorites[1].resolvedMediaType, .image)
    }

    func test_favorite_postsToCorrectPath() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/favorites/42")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = """
            {"code":0,"message":"OK","data":{"id":99,"messageId":42},"timestamp":0}
            """
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        let result = try await repo.favorite(messageId: 42)
        XCTAssertEqual(result.id, 99)
        XCTAssertEqual(result.messageId, 42)
    }

    func test_unfavorite_deletesCorrectPath() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/favorites/42")
            XCTAssertEqual(request.httpMethod, "DELETE")
            let body = #"{"code":0,"message":"OK","data":null,"timestamp":0}"#
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        try await repo.unfavorite(messageId: 42)
    }

    private func makeRepository() -> FavoriteRepositoryImpl {
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
        return FavoriteRepositoryImpl(apiClient: client)
    }
}
