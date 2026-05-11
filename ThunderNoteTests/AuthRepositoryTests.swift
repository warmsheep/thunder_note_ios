import XCTest
@testable import ThunderNote

final class AuthRepositoryTests: XCTestCase {
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

    func test_login_returnsLoginResponseAndForwardsBody() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/auth/login")
            let body = """
            {"code":0,"message":"OK","data":{"accessToken":"a","refreshToken":"r","tokenType":"Bearer","expiresIn":3600000,"user":{"id":1,"username":"alice"}},"timestamp":0}
            """
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        let response = try await repo.login(username: "alice", password: "secret123")
        XCTAssertEqual(response.user.username, "alice")
    }

    func test_register_validatesShortUsername() async {
        let repo = makeRepository()
        do {
            try await repo.register(username: "ab", email: "a@b.com", password: "secret123")
            XCTFail("应校验失败")
        } catch let error as AuthRepositoryImpl.ValidationError {
            XCTAssertEqual(error, .usernameLength)
        } catch {
            XCTFail("错误类型不匹配")
        }
    }

    func test_register_validatesEmailFormat() async {
        let repo = makeRepository()
        do {
            try await repo.register(username: "alice", email: "not-an-email", password: "secret123")
            XCTFail("应校验失败")
        } catch let error as AuthRepositoryImpl.ValidationError {
            XCTAssertEqual(error, .emailFormat)
        } catch {
            XCTFail("错误类型不匹配")
        }
    }

    func test_register_validatesShortPassword() async {
        let repo = makeRepository()
        do {
            try await repo.register(username: "alice", email: "a@b.com", password: "abc")
            XCTFail("应校验失败")
        } catch let error as AuthRepositoryImpl.ValidationError {
            XCTAssertEqual(error, .passwordLength)
        } catch {
            XCTFail("错误类型不匹配")
        }
    }

    func test_changePassword_rejectsSameAsOld() async {
        let repo = makeRepository()
        do {
            try await repo.changePassword(currentPassword: "secret123", newPassword: "secret123")
            XCTFail("应校验失败")
        } catch let error as AuthRepositoryImpl.ValidationError {
            XCTAssertEqual(error, .newPasswordSameAsOld)
        } catch {
            XCTFail("错误类型不匹配：\(error)")
        }
    }

    func test_logout_postsToLogoutEndpoint() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/logout")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = #"{"code":0,"message":"OK","data":null,"timestamp":0}"#
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(body.utf8))
        }
        let repo = makeRepository()
        try await repo.logout()
    }

    private func makeRepository() -> AuthRepositoryImpl {
        let serverConfig = StaticServerConfig(baseURL: baseURL)
        let tokenStore = InMemoryTokenStore()
        // 让 logout 等带 auth 的接口能注入 Authorization
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
        return AuthRepositoryImpl(apiClient: client)
    }
}
