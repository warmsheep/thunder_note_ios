import XCTest
@testable import ThunderNote

/// D2-I7-01 / I7-02 / I7-03 同步主链单测。
final class SyncRepositoryTests: XCTestCase {

    private var session: URLSession!
    private let baseURL = URL(string: "https://example.com")!
    private var dbURL: URL!
    private var database: TNDatabase!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = MockURLProtocol.makeSession()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tn-sync-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("sync.sqlite3")
        database = try! TNDatabase(fileURL: dbURL)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        session = nil
        database = nil
        if let url = dbURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        super.tearDown()
    }

    // MARK: - bootstrap

    func test_bootstrap_callsBootstrapEndpoint_andPersistsServerTime() async throws {
        let payload = """
        {"code":0,"message":"OK","data":{
          "notes":[{"id":1,"title":"n1"}],
          "collections":[{"id":7}],
          "messages":[{"id":11,"createdAt":"2026-05-01T10:00:00"},{"id":12,"createdAt":"2026-05-01T11:00:00"}],
          "favorites":[],
          "serverTime":"2026-05-01T12:00:00",
          "bootstrap":true
        },"timestamp":0}
        """
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/sync/bootstrap")
            XCTAssertEqual(request.httpMethod, "POST")
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }
        let dao = SQLiteSyncMetaDao(database: database)
        let repo = makeRepository(dao: dao)
        let response = try await repo.bootstrap()
        XCTAssertEqual(response.bootstrap, true)
        XCTAssertEqual(response.notes.count, 1)
        XCTAssertEqual(response.messages.count, 2)
        XCTAssertEqual(response.maxMessageCreatedAt, "2026-05-01T11:00:00")
        XCTAssertEqual(try dao.loadLastMessageCreatedAt(username: "alice"), "2026-05-01T11:00:00")
        XCTAssertEqual(try dao.loadServerTime(username: "alice"), "2026-05-01T12:00:00")
    }

    // MARK: - pull

    func test_pull_sendsLastMessageCreatedAtFromDao() async throws {
        let dao = SQLiteSyncMetaDao(database: database)
        try dao.upsert(username: "alice", lastMessageCreatedAt: "2026-05-01T11:00:00", serverTime: nil)

        let probe = SendableBox<String?>(value: nil)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/sync/pull")
            XCTAssertEqual(request.httpMethod, "POST")
            if let body = request.httpBodyOrStreamData() {
                let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
                probe.set(json?["lastMessageCreatedAt"] as? String)
            }
            let payload = """
            {"code":0,"message":"OK","data":{
              "notes":[],"collections":[],"messages":[],"favorites":[],
              "serverTime":"2026-05-01T12:30:00"
            },"timestamp":0}
            """
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }
        let repo = makeRepository(dao: dao)
        _ = try await repo.pull()
        XCTAssertEqual(probe.value, "2026-05-01T11:00:00")
        // 服务端没返新消息 → last_message_created_at 不被覆盖；server_time 推进。
        XCTAssertEqual(try dao.loadLastMessageCreatedAt(username: "alice"), "2026-05-01T11:00:00")
        XCTAssertEqual(try dao.loadServerTime(username: "alice"), "2026-05-01T12:30:00")
    }

    func test_pull_advancesLastMessageCreatedAt_whenNewMessagesReturned() async throws {
        let dao = SQLiteSyncMetaDao(database: database)
        try dao.upsert(username: "alice", lastMessageCreatedAt: "2026-05-01T10:00:00", serverTime: nil)
        let payload = """
        {"code":0,"message":"OK","data":{
          "notes":[],"collections":[],
          "messages":[
            {"id":99,"createdAt":"2026-05-01T12:00:00"},
            {"id":100,"createdAt":"2026-05-01T13:30:00"}
          ],
          "favorites":[],
          "serverTime":"2026-05-01T13:31:00"
        },"timestamp":0}
        """
        MockURLProtocol.handler = { request in
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }
        let repo = makeRepository(dao: dao)
        let response = try await repo.pull()
        XCTAssertEqual(response.messages.count, 2)
        XCTAssertEqual(try dao.loadLastMessageCreatedAt(username: "alice"), "2026-05-01T13:30:00")
        XCTAssertEqual(try dao.loadServerTime(username: "alice"), "2026-05-01T13:31:00")
    }

    // MARK: - push

    func test_push_postsPayloadAndParsesProcessed() async throws {
        let probe = SendableBox<[String: Any]?>(value: nil)
        let payload = """
        {"code":0,"message":"OK","data":{
          "accepted":true,
          "processed":{"notes":2,"collections":1,"messages":3,"favorites":0},
          "serverTime":"2026-05-01T14:00:00"
        },"timestamp":0}
        """
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/sync/push")
            XCTAssertEqual(request.httpMethod, "POST")
            if let body = request.httpBodyOrStreamData() {
                probe.set(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
            }
            return (HTTPURLResponse.make(url: request.url!, status: 200), Data(payload.utf8))
        }
        let dao = SQLiteSyncMetaDao(database: database)
        let repo = makeRepository(dao: dao)
        let push = SyncPushRequest(
            notes: [.init(id: 1, title: "n1")],
            messages: [.init(clientRequestId: "req-1", content: "hello")]
        )
        let response = try await repo.push(push)
        XCTAssertTrue(response.accepted)
        XCTAssertEqual(response.processed.notes, 2)
        XCTAssertEqual(response.processed.messages, 3)
        XCTAssertEqual(try dao.loadServerTime(username: "alice"), "2026-05-01T14:00:00")
        // 提交 body 形态
        let body = probe.value
        XCTAssertNotNil(body?["notes"])
        XCTAssertNotNil(body?["messages"])
    }

    // MARK: - factory

    private func makeRepository(dao: SyncMetaDao) -> SyncRepositoryImpl {
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
        return SyncRepositoryImpl(
            apiClient: client,
            syncMetaDao: dao,
            usernameProvider: { "alice" }
        )
    }
}

private final class SendableBox<T>: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.box")
    private var _value: T
    init(value: T) { _value = value }
    var value: T { queue.sync { _value } }
    func set(_ v: T) { queue.sync { _value = v } }
}

private extension URLRequest {
    /// MockURLProtocol 在某些路径下使用 inputStream，这里给一个统一抽取 body 的方法。
    func httpBodyOrStreamData() -> Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
