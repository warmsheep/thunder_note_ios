import XCTest
@testable import ThunderNote

/// D2-I7-05 / I7-08 Step 2A：SyncCoordinator 与 PendingMessageDao / SyncEngine 集成。
final class SyncCoordinatorPendingTests: XCTestCase {

    private var dbURL: URL!
    private var database: TNDatabase!
    private var dao: SQLitePendingMessageDao!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tn-coord-pending-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("coord.sqlite3")
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

    @MainActor
    func test_manualSync_drainsPendingBeforePushPull_andReportsPendingCount() async throws {
        // 准备：2 条 QUEUED，sender 全部成功
        _ = try dao.insert(.alice(content: "a"))
        _ = try dao.insert(.alice(content: "b"))
        let sender = AlwaysSucceedSender()
        let engine = SyncEngine(dao: dao, sender: sender, usernameProvider: { "alice" })

        let repo = StubSyncRepository()
        repo.pushResponse = SyncPushResponse(accepted: true)
        repo.pullResponse = SyncPullResponse(serverTime: "S")

        let coord = SyncCoordinator(
            syncRepository: repo,
            pendingMessageDao: dao,
            syncEngine: engine,
            usernameProvider: { "alice" }
        )
        await engine.setOnQueueChanged { [weak coord] in coord?.refreshPendingCount() }

        // 初始 pendingCount 由 manualSync 调用末尾刷新；先手动 reload 一次确认初值。
        XCTAssertEqual(coord.pendingCount, 0) // @Published 初值

        await coord.manualSync()

        XCTAssertEqual(sender.sentCount.value, 2)
        XCTAssertEqual(repo.pushCount, 1)
        XCTAssertEqual(repo.pullCount, 1)
        // drain 全成功 → pendingCount 应为 0
        XCTAssertEqual(coord.pendingCount, 0)
        XCTAssertEqual(coord.state, .idle)
    }

    @MainActor
    func test_manualSync_failedSends_increasePendingCount() async throws {
        _ = try dao.insert(.alice(content: "x"))
        let sender = AlwaysFailSender()
        let engine = SyncEngine(dao: dao, sender: sender, usernameProvider: { "alice" }, maxAttempts: 3)
        let repo = StubSyncRepository()
        repo.pushResponse = SyncPushResponse(accepted: true)
        repo.pullResponse = SyncPullResponse()

        let coord = SyncCoordinator(
            syncRepository: repo,
            pendingMessageDao: dao,
            syncEngine: engine,
            usernameProvider: { "alice" }
        )
        await coord.manualSync()
        // 1 条 QUEUED → FAILED → 仍计 pendingCount
        XCTAssertEqual(coord.pendingCount, 1)
    }

    @MainActor
    func test_retryPending_resetsAndDispatches() async throws {
        let failed = PendingMessageLocal(
            username: "alice", conversationKey: 7, content: "retry",
            status: .failed, createdAt: 0, attemptCount: 5
        )
        let id = try dao.insert(failed)

        let sender = AlwaysSucceedSender()
        let engine = SyncEngine(dao: dao, sender: sender, usernameProvider: { "alice" }, maxAttempts: 3)
        let coord = SyncCoordinator(
            syncRepository: StubSyncRepository(),
            pendingMessageDao: dao,
            syncEngine: engine,
            usernameProvider: { "alice" }
        )
        await coord.retryPending(localId: id)
        XCTAssertNil(try dao.findByLocalId(id))
        XCTAssertEqual(coord.pendingCount, 0)
    }

    @MainActor
    func test_resetForSignOut_clearsPendingMessagesForUser() async throws {
        _ = try dao.insert(.alice(content: "a"))
        _ = try dao.insert(.alice(content: "b"))
        _ = try dao.insert(PendingMessageLocal(
            username: "bob", conversationKey: 7, content: "bob-row",
            status: .queued, createdAt: 0
        ))
        let coord = SyncCoordinator(
            syncRepository: StubSyncRepository(),
            pendingMessageDao: dao,
            syncEngine: nil,
            usernameProvider: { "alice" }
        )
        coord.resetForSignOut()
        XCTAssertEqual(try dao.listAll(username: "alice"), [])
        XCTAssertEqual(try dao.listAll(username: "bob").count, 1) // bob 未被清
    }
}

private extension PendingMessageLocal {
    static func alice(content: String) -> PendingMessageLocal {
        PendingMessageLocal(
            username: "alice", conversationKey: 7, content: content,
            status: .queued, createdAt: 0
        )
    }
}

private final class AlwaysSucceedSender: PendingMessageSender, @unchecked Sendable {
    let sentCount = SendableInt(0)
    func send(_ pending: PendingMessageLocal) async throws -> Int64? {
        sentCount.increment()
        return 1
    }
}

private final class AlwaysFailSender: PendingMessageSender, @unchecked Sendable {
    func send(_ pending: PendingMessageLocal) async throws -> Int64? {
        throw APIError.business(code: 500, message: "boom")
    }
}

/// 本文件局部的 SyncRepository stub（与 SyncCoordinatorTests.swift 的 fileprivate 实现互相独立）。
private final class StubSyncRepository: SyncRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.coordp.repo")
    private var _bootstrapCount = 0
    private var _pullCount = 0
    private var _pushCount = 0
    var bootstrapResponse: SyncPullResponse = SyncPullResponse()
    var pullResponse: SyncPullResponse = SyncPullResponse()
    var pushResponse: SyncPushResponse = SyncPushResponse()

    var bootstrapCount: Int { queue.sync { _bootstrapCount } }
    var pullCount: Int { queue.sync { _pullCount } }
    var pushCount: Int { queue.sync { _pushCount } }

    func bootstrap() async throws -> SyncPullResponse {
        queue.sync { _bootstrapCount += 1 }
        return bootstrapResponse
    }
    func pull() async throws -> SyncPullResponse {
        queue.sync { _pullCount += 1 }
        return pullResponse
    }
    func push(_ payload: SyncPushRequest) async throws -> SyncPushResponse {
        queue.sync { _pushCount += 1 }
        return pushResponse
    }
}

private final class SendableInt: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.coord.box")
    private var _value: Int
    init(_ value: Int) { _value = value }
    var value: Int { queue.sync { _value } }
    func increment() { queue.sync { _value += 1 } }
}
