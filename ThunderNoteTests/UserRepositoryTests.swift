import XCTest
@testable import ThunderNote

final class UserRepositoryTests: XCTestCase {
    private var session: URLSession!
    private let baseURL = URL(string: "https://example.com/")!
    private var defaultsSuiteName: String!
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        session = MockURLProtocol.makeSession()
        MockURLProtocol.reset()
        defaultsSuiteName = "UserRepositoryTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: defaultsSuiteName)!
    }

    override func tearDown() {
        MockURLProtocol.reset()
        userDefaults.removePersistentDomain(forName: defaultsSuiteName)
        super.tearDown()
    }

    func test_fetchProfile_cachesAndPersistsToDefaults() async throws {
        let profile = UserProfile(id: 1, userId: 7, bio: "hello", avatar: "💼", nickname: "Alice")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/users/profile")
            XCTAssertEqual(request.httpMethod, "POST")
            return (
                HTTPURLResponse.make(url: request.url!, status: 200),
                try Self.successData(profile)
            )
        }
        let repo = makeRepository(username: "alice")

        let fetched = try await repo.fetchProfile(forceRefresh: false)

        XCTAssertEqual(fetched.nickname, "Alice")
        XCTAssertEqual(repo.cachedProfile()?.bio, "hello")
        XCTAssertNotNil(userDefaults.data(forKey: UserRepositoryImpl.cacheKey(for: "alice")))
    }

    func test_fetchProfile_withinCooldown_skipsNetwork() async throws {
        let nowRef = MutableNow(seconds: 1000)
        let counter = CallCounter()
        MockURLProtocol.handler = { request in
            counter.bump()
            let bio = "v\(counter.value)"
            return (
                HTTPURLResponse.make(url: request.url!, status: 200),
                try Self.successData(UserProfile(bio: bio))
            )
        }
        let repo = makeRepository(username: "alice", now: nowRef.closure)

        _ = try await repo.fetchProfile(forceRefresh: false)
        nowRef.advance(by: 5.0)  // < 10s cooldown
        let second = try await repo.fetchProfile(forceRefresh: false)

        XCTAssertEqual(second.bio, "v1", "cooldown 内应复用缓存")
        XCTAssertEqual(counter.value, 1, "cooldown 内不应再次发起请求")
    }

    func test_fetchProfile_forceRefresh_overridesCooldown() async throws {
        let nowRef = MutableNow(seconds: 1000)
        let counter = CallCounter()
        MockURLProtocol.handler = { request in
            counter.bump()
            return (
                HTTPURLResponse.make(url: request.url!, status: 200),
                try Self.successData(UserProfile(bio: "v\(counter.value)"))
            )
        }
        let repo = makeRepository(username: "alice", now: nowRef.closure)
        _ = try await repo.fetchProfile(forceRefresh: false)
        nowRef.advance(by: 1.0)
        let refreshed = try await repo.fetchProfile(forceRefresh: true)
        XCTAssertEqual(refreshed.bio, "v2")
        XCTAssertEqual(counter.value, 2)
    }

    func test_fetchProfile_afterCooldownExpires_refetches() async throws {
        let nowRef = MutableNow(seconds: 1000)
        let counter = CallCounter()
        MockURLProtocol.handler = { request in
            counter.bump()
            return (
                HTTPURLResponse.make(url: request.url!, status: 200),
                try Self.successData(UserProfile(bio: "v\(counter.value)"))
            )
        }
        let repo = makeRepository(username: "alice", now: nowRef.closure)
        _ = try await repo.fetchProfile(forceRefresh: false)
        nowRef.advance(by: 10.5)  // > 10s cooldown
        let refreshed = try await repo.fetchProfile(forceRefresh: false)
        XCTAssertEqual(refreshed.bio, "v2")
    }

    func test_updateProfile_writesCache() async throws {
        let updated = UserProfile(bio: "newBio", nickname: "Bob")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/users/profile")
            XCTAssertEqual(request.httpMethod, "PUT")
            return (
                HTTPURLResponse.make(url: request.url!, status: 200),
                try Self.successData(updated)
            )
        }
        let repo = makeRepository(username: "alice")

        let result = try await repo.updateProfile(UserProfile(bio: "newBio", nickname: "Bob"))

        XCTAssertEqual(result.nickname, "Bob")
        XCTAssertEqual(repo.cachedProfile()?.bio, "newBio")
    }

    func test_updateAvatar_updatesLocalAvatarInCache() async throws {
        let initial = UserProfile(bio: "hello", avatar: "💼", nickname: "Alice")
        let routes = ResponseRoutes()
        routes.set("/api/users/profile") {
            try Self.successData(initial)
        }
        routes.set("/api/users/avatar") {
            try Self.successData("📚")
        }
        MockURLProtocol.handler = { request in
            return (
                HTTPURLResponse.make(url: request.url!, status: 200),
                try routes.data(for: request.url?.path ?? "")
            )
        }
        let repo = makeRepository(username: "alice")
        _ = try await repo.fetchProfile(forceRefresh: false)

        try await repo.updateAvatar("📚")

        XCTAssertEqual(repo.cachedProfile()?.avatar, "📚")
        XCTAssertEqual(repo.cachedProfile()?.nickname, "Alice")
    }

    func test_clearCache_removesMemoryAndDefaults() async throws {
        let profile = UserProfile(bio: "x")
        MockURLProtocol.handler = { request in
            return (
                HTTPURLResponse.make(url: request.url!, status: 200),
                try Self.successData(profile)
            )
        }
        let repo = makeRepository(username: "alice")
        _ = try await repo.fetchProfile(forceRefresh: false)
        XCTAssertNotNil(userDefaults.data(forKey: UserRepositoryImpl.cacheKey(for: "alice")))

        repo.clearCache()

        XCTAssertNil(repo.cachedProfile())
        XCTAssertNil(userDefaults.data(forKey: UserRepositoryImpl.cacheKey(for: "alice")))
    }

    func test_initLoadsPersistedCache_forSameUsername() async throws {
        let profile = UserProfile(bio: "fromDefaults", nickname: "PrevUser")
        MockURLProtocol.handler = { request in
            return (
                HTTPURLResponse.make(url: request.url!, status: 200),
                try Self.successData(profile)
            )
        }
        let firstRepo = makeRepository(username: "alice")
        _ = try await firstRepo.fetchProfile(forceRefresh: false)

        // 新建一个 repo（模拟冷启动）应读到 UserDefaults 的缓存。
        let secondRepo = makeRepository(username: "alice")
        XCTAssertEqual(secondRepo.cachedProfile()?.nickname, "PrevUser")
    }

    // MARK: - Helpers

    private func makeRepository(
        username: String,
        now: @Sendable @escaping () -> Date = { Date() }
    ) -> UserRepositoryImpl {
        let serverConfig = StaticServerConfig(baseURL: baseURL)
        let tokenStore = InMemoryTokenStore()
        tokenStore.save(loginResponse: LoginResponse(
            accessToken: "tok",
            refreshToken: "ref",
            tokenType: "Bearer",
            expiresIn: 3600,
            user: User(id: 7, username: username)
        ))
        let accessor = DefaultTokenAccessor(tokenStore: tokenStore)
        let client = APIClient(
            session: session,
            serverConfigStore: serverConfig,
            tokenAccessor: accessor,
            userAgent: "ThunderNoteTest/0.0",
            acceptLanguage: "zh-Hans"
        )
        return UserRepositoryImpl(
            apiClient: client,
            userDefaults: userDefaults,
            usernameProvider: { username },
            now: now
        )
    }

    /// 把任意 `Encodable` 包装成 `{"code":0,"message":"OK","data":...,"timestamp":0}`。
    /// `ApiResponse` 本身仅是 Decodable，无法直接 encode；这里手动拼接 outer JSON。
    private static func successData<T: Encodable>(_ value: T) throws -> Data {
        let inner = try JSONEncoder.tnDefault.encode(value)
        let innerString = String(data: inner, encoding: .utf8) ?? "null"
        let payload = "{\"code\":0,\"message\":\"OK\",\"data\":\(innerString),\"timestamp\":0}"
        return Data(payload.utf8)
    }
}

private final class MutableNow: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.user.mutablenow")
    private var seconds: TimeInterval
    init(seconds: TimeInterval) { self.seconds = seconds }
    func advance(by delta: TimeInterval) { queue.sync { self.seconds += delta } }
    var closure: @Sendable () -> Date {
        { [self] in Date(timeIntervalSince1970: self.queue.sync { self.seconds }) }
    }
}

private final class CallCounter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.user.callcounter")
    private var _value: Int = 0
    func bump() { queue.sync { _value += 1 } }
    var value: Int { queue.sync { _value } }
}

private final class ResponseRoutes: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.user.routes")
    private var routes: [String: () throws -> Data] = [:]
    func set(_ path: String, builder: @escaping () throws -> Data) {
        queue.sync { routes[path] = builder }
    }
    func data(for path: String) throws -> Data {
        let builder = queue.sync { routes[path] }
        guard let builder else {
            throw NSError(domain: "tests", code: 404, userInfo: [NSLocalizedDescriptionKey: "no route: \(path)"])
        }
        return try builder()
    }
}
