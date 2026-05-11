import XCTest
@testable import ThunderNote

/// D2-I7-05 SyncEngine actor 单测。
final class SyncEngineTests: XCTestCase {

    private var dbURL: URL!
    private var database: TNDatabase!
    private var dao: SQLitePendingMessageDao!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tn-syncengine-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("engine.sqlite3")
        database = try! TNDatabase(fileURL: dbURL)
        dao = SQLitePendingMessageDao(database: database)
    }

    override func tearDown() {
        dao = nil
        database = nil
        if let url = dbURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        super.tearDown()
    }

    // MARK: - 成功路径

    func test_drain_dispatchesAllQueued_andRemovesSuccessful() async throws {
        _ = try dao.insert(.alice(content: "a"))
        _ = try dao.insert(.alice(content: "b"))
        let sender = ProgrammableSender()
        sender.behavior = .succeed(serverId: 100)
        let engine = SyncEngine(dao: dao, sender: sender, usernameProvider: { "alice" }, maxAttempts: 3)
        let result = await engine.drain()
        XCTAssertEqual(result, .dispatched(2))
        XCTAssertEqual(sender.sentContents.value.sorted(), ["a", "b"])
        // 成功后行被删除
        XCTAssertEqual(try dao.countDispatchable(username: "alice"), 0)
    }

    func test_drain_emptyQueue_returnsIdle() async {
        let sender = ProgrammableSender()
        sender.behavior = .succeed(serverId: nil)
        let engine = SyncEngine(dao: dao, sender: sender, usernameProvider: { "alice" })
        let result = await engine.drain()
        XCTAssertEqual(result, .idle)
    }

    // MARK: - 失败路径

    func test_drain_failureMarksFailed_andStopsAtMaxAttempts() async throws {
        let id = try dao.insert(.alice(content: "fails"))
        let sender = ProgrammableSender()
        sender.behavior = .fail(error: APIError.business(code: 500, message: "服务异常"))
        let engine = SyncEngine(dao: dao, sender: sender, usernameProvider: { "alice" }, maxAttempts: 3)
        // drain 内部循环：QUEUED → FAILED 一直尝试到 attempt == maxAttempts 才停。
        _ = await engine.drain()
        let after = try dao.findByLocalId(id)
        XCTAssertEqual(after?.status, .failed)
        XCTAssertEqual(after?.attemptCount, 3)
        XCTAssertEqual(after?.errorMessage, "服务异常")
        // 再 drain：attempt 已到 maxAttempts，直接 break，不再调 sender。
        let beforeSentCount = sender.sentContents.value.count
        _ = await engine.drain()
        XCTAssertEqual(sender.sentContents.value.count, beforeSentCount)
        XCTAssertEqual(try dao.findByLocalId(id)?.attemptCount, 3)
    }

    func test_drain_stopsRetryingPastMaxAttempts() async throws {
        var initial = PendingMessageLocal.alice(content: "max")
        initial.status = .failed
        initial.attemptCount = 5
        let id = try dao.insert(initial)
        let sender = ProgrammableSender()
        sender.behavior = .fail(error: APIError.business(code: 500, message: "x"))
        let engine = SyncEngine(dao: dao, sender: sender, usernameProvider: { "alice" }, maxAttempts: 5)
        let result = await engine.drain()
        XCTAssertEqual(result, .idle)
        XCTAssertEqual(sender.sentContents.value, [])
        // attempt 不应增加
        let after = try dao.findByLocalId(id)
        XCTAssertEqual(after?.attemptCount, 5)
    }

    // MARK: - retry / remove

    func test_retry_resetsAttemptAndDispatches() async throws {
        var failed = PendingMessageLocal.alice(content: "retry-me")
        failed.status = .failed
        failed.attemptCount = 4
        failed.errorMessage = "old"
        let id = try dao.insert(failed)
        let sender = ProgrammableSender()
        sender.behavior = .succeed(serverId: 42)
        let engine = SyncEngine(dao: dao, sender: sender, usernameProvider: { "alice" }, maxAttempts: 3)
        await engine.retry(localId: id)
        // 成功后行被删除
        XCTAssertNil(try dao.findByLocalId(id))
        XCTAssertEqual(sender.sentContents.value, ["retry-me"])
    }

    func test_remove_deletesRow() async throws {
        let id = try dao.insert(.alice(content: "x"))
        let engine = SyncEngine(dao: dao, sender: ProgrammableSender(), usernameProvider: { "alice" })
        await engine.remove(localId: id)
        XCTAssertNil(try dao.findByLocalId(id))
    }

    // MARK: - listener

    func test_listener_firesOnQueueChanges() async throws {
        let hits = HitBox()
        let engine = SyncEngine(dao: dao, sender: ProgrammableSender(), usernameProvider: { "alice" })
        await engine.setOnQueueChanged { hits.increment() }
        _ = try await engine.enqueue(.alice(content: "x"))
        // enqueue 触发一次 listener
        XCTAssertGreaterThanOrEqual(hits.value, 1)
    }

    // MARK: - username provider

    func test_drain_isNoop_whenUsernameNil() async throws {
        _ = try dao.insert(.alice(content: "x"))
        let sender = ProgrammableSender()
        sender.behavior = .succeed(serverId: nil)
        let engine = SyncEngine(dao: dao, sender: sender, usernameProvider: { nil })
        let result = await engine.drain()
        XCTAssertEqual(result, .idle)
        XCTAssertEqual(sender.sentContents.value, [])
    }
}

private final class ProgrammableSender: PendingMessageSender, @unchecked Sendable {
    enum Behavior {
        case succeed(serverId: Int64?)
        case fail(error: Error)
    }
    var behavior: Behavior = .succeed(serverId: nil)
    let sentContents = SendableBox<[String]>(value: [])

    func send(_ pending: PendingMessageLocal) async throws -> Int64? {
        sentContents.mutate { $0.append(pending.content ?? "") }
        switch behavior {
        case .succeed(let id): return id
        case .fail(let err): throw err
        }
    }
}

private extension PendingMessageLocal {
    static func alice(content: String, createdAt: Int64 = 0) -> PendingMessageLocal {
        PendingMessageLocal(
            username: "alice",
            conversationKey: 7,
            content: content,
            status: .queued,
            createdAt: createdAt
        )
    }
}

private final class SendableBox<T>: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.engine.box")
    private var _value: T
    init(value: T) { _value = value }
    var value: T { queue.sync { _value } }
    func set(_ v: T) { queue.sync { _value = v } }
    func mutate(_ f: (inout T) -> Void) { queue.sync { f(&_value) } }
}

private final class HitBox: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.engine.hit")
    private var _value = 0
    var value: Int { queue.sync { _value } }
    func increment() { queue.sync { _value += 1 } }
}
