import XCTest
@testable import ThunderNote

/// 跨闭包共享的并发安全计数器，用于 mock handler 中累计调用次数。
final class AtomicCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var _businessHits = 0
    private var _refreshHits = 0

    func incrementBusiness() -> Int {
        lock.lock(); defer { lock.unlock() }
        _businessHits += 1
        return _businessHits
    }

    func incrementRefresh() {
        lock.lock(); defer { lock.unlock() }
        _refreshHits += 1
    }

    var businessHits: Int {
        lock.lock(); defer { lock.unlock() }
        return _businessHits
    }

    var refreshHits: Int {
        lock.lock(); defer { lock.unlock() }
        return _refreshHits
    }
}

final class APIClientTests: XCTestCase {
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

    // MARK: - 成功用例

    func test_send_decodesApiResponseSuccess() async throws {
        let payload = """
        {"code":0,"message":"OK","data":{"accessToken":"a","refreshToken":"r","tokenType":"Bearer","expiresIn":3600000,"user":{"id":1,"username":"alice"}},"timestamp":0}
        """
        MockURLProtocol.handler = { request in
            (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }

        let client = makeClient()
        let endpoint = Endpoint<LoginResponse>(method: .post, path: "/api/auth/login", requiresAuth: false)
        let response = try await client.send(endpoint)

        XCTAssertEqual(response.accessToken, "a")
        XCTAssertEqual(response.refreshToken, "r")
        XCTAssertEqual(response.user.username, "alice")

        let lastRequest = MockURLProtocol.requestLog.last
        XCTAssertEqual(lastRequest?.url?.absoluteString, "https://example.com/api/auth/login")
        XCTAssertEqual(lastRequest?.httpMethod, "POST")
    }

    // MARK: - 业务错误

    func test_send_mapsBusinessError() async throws {
        let payload = #"{"code":40000,"message":"参数错误","data":null,"timestamp":0}"#
        MockURLProtocol.handler = { request in
            (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }
        let client = makeClient()
        let endpoint = Endpoint<LoginResponse>(method: .post, path: "/api/auth/login", requiresAuth: false)
        do {
            _ = try await client.send(endpoint)
            XCTFail("应抛业务错误")
        } catch let error as APIError {
            if case .business(let code, let message) = error {
                XCTAssertEqual(code, 40000)
                XCTAssertEqual(message, "参数错误")
            } else {
                XCTFail("错误类型不匹配：\(error)")
            }
        }
    }

    // MARK: - 网络错误

    func test_send_mapsTransportError() async throws {
        MockURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let client = makeClient()
        let endpoint = Endpoint<LoginResponse>(method: .post, path: "/api/auth/login", requiresAuth: false)
        do {
            _ = try await client.send(endpoint)
            XCTFail("应抛 transport 错误")
        } catch let error as APIError {
            if case .transport = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("错误类型不匹配：\(error)")
            }
        }
    }

    // MARK: - HTTP 5xx

    func test_send_mapsHttpServerError() async throws {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse.make(url: request.url!, status: 503), Data("Service Unavailable".utf8))
        }
        let client = makeClient()
        let endpoint = Endpoint<LoginResponse>(method: .post, path: "/api/auth/login", requiresAuth: false)
        do {
            _ = try await client.send(endpoint)
            XCTFail("应抛 HTTP 错误")
        } catch let error as APIError {
            if case .http(let status, _) = error {
                XCTAssertEqual(status, 503)
            } else {
                XCTFail("错误类型不匹配：\(error)")
            }
        }
    }

    // MARK: - Authorization 注入

    func test_send_injectsAuthorizationHeaderWhenTokenAvailable() async throws {
        let tokenStore = InMemoryTokenStore()
        tokenStore.save(loginResponse: LoginResponse(
            accessToken: "ACC",
            refreshToken: "REF",
            tokenType: "Bearer",
            expiresIn: 3600000,
            user: User(id: 1, username: "alice")
        ))

        MockURLProtocol.handler = { request in
            let body = #"{"code":0,"message":"OK","data":{"id":1,"username":"alice"},"timestamp":0}"#
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }

        let client = makeClient(tokenStore: tokenStore)
        let endpoint = Endpoint<User>(method: .get, path: "/api/users/me", requiresAuth: true)
        _ = try await client.send(endpoint)

        let auth = MockURLProtocol.requestLog.last?.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(auth, "Bearer ACC")
    }

    // MARK: - 401 → 刷新 → 重试一次

    func test_send_refreshesOnUnauthorizedAndRetriesOnce() async throws {
        let tokenStore = InMemoryTokenStore()
        tokenStore.save(loginResponse: LoginResponse(
            accessToken: "OLD",
            refreshToken: "REF",
            tokenType: "Bearer",
            expiresIn: 3600000,
            user: User(id: 1, username: "alice")
        ))

        let counters = AtomicCounters()

        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path == "/api/auth/refresh" {
                counters.incrementRefresh()
                let body = """
                {"code":0,"message":"OK","data":{"accessToken":"NEW","refreshToken":"REF2","tokenType":"Bearer","expiresIn":3600000,"user":{"id":1,"username":"alice"}},"timestamp":0}
                """
                return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
            }
            let count = counters.incrementBusiness()
            if count == 1 {
                let body = #"{"code":40100,"message":"未认证","data":null,"timestamp":0}"#
                return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
            }
            let body = #"{"code":0,"message":"OK","data":{"id":1,"username":"alice"},"timestamp":0}"#
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }

        let client = makeClient(tokenStore: tokenStore)
        let endpoint = Endpoint<User>(method: .get, path: "/api/users/me", requiresAuth: true)
        let user = try await client.send(endpoint)

        XCTAssertEqual(user.username, "alice")
        XCTAssertEqual(counters.refreshHits, 1, "应仅刷新一次")
        XCTAssertEqual(tokenStore.loadAccessToken(), "NEW", "刷新成功后应保存新 token")

        let retryAuth = MockURLProtocol.requestLog.last?.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(retryAuth, "Bearer NEW")
    }

    func test_send_refreshFailureClearsSessionAndThrowsUnauthenticated() async throws {
        let tokenStore = InMemoryTokenStore()
        tokenStore.save(loginResponse: LoginResponse(
            accessToken: "OLD",
            refreshToken: "REF",
            tokenType: "Bearer",
            expiresIn: 3600000,
            user: User(id: 1, username: "alice")
        ))

        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path == "/api/auth/refresh" {
                let body = #"{"code":40100,"message":"refresh expired","data":null,"timestamp":0}"#
                return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
            }
            let body = #"{"code":40100,"message":"未认证","data":null,"timestamp":0}"#
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }

        let client = makeClient(tokenStore: tokenStore)
        let endpoint = Endpoint<User>(method: .get, path: "/api/users/me", requiresAuth: true)
        do {
            _ = try await client.send(endpoint)
            XCTFail("应抛 unauthenticated")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthenticated)
        }
        XCTAssertNil(tokenStore.loadAccessToken(), "刷新失败应清空 token")
    }

    // MARK: - 工厂

    private func makeClient(tokenStore: TokenStoring = InMemoryTokenStore()) -> APIClient {
        let serverConfig = StaticServerConfig(baseURL: baseURL)
        let accessor = DefaultTokenAccessor(tokenStore: tokenStore)
        return APIClient(
            session: session,
            serverConfigStore: serverConfig,
            tokenAccessor: accessor,
            userAgent: "ThunderNoteTest/0.0",
            acceptLanguage: "zh-Hans"
        )
    }
}
