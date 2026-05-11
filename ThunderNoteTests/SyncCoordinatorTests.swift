import XCTest
@testable import ThunderNote

/// D2-I7-08 手动同步 + bootstrap 触发器单测。
final class SyncCoordinatorTests: XCTestCase {

    @MainActor
    func test_bootstrapIfNeeded_runsExactlyOnce_whileTaskInFlight() async {
        let repo = StubSyncRepository()
        repo.bootstrapResponse = SyncPullResponse(serverTime: "S1")
        let coord = SyncCoordinator(syncRepository: repo)
        coord.bootstrapIfNeeded()
        coord.bootstrapIfNeeded() // 第二次应被去重，等待第一次完成
        await waitForState(coord) { _ in repo.bootstrapCount >= 1 }
        // 给 runBootstrap 走完 lastServerTime / state 赋值。
        await waitForState(coord) { $0.lastServerTime == "S1" }
        XCTAssertEqual(repo.bootstrapCount, 1)
        XCTAssertEqual(coord.state, .idle)
    }

    @MainActor
    func test_manualSync_pushThenPull_andRefreshesHooks() async {
        let repo = StubSyncRepository()
        repo.pullResponse = SyncPullResponse(serverTime: "S2")
        repo.pushResponse = SyncPushResponse(accepted: true, processed: .init(messages: 0), serverTime: "S2")
        let hookHits = HitBox()
        let coord = SyncCoordinator(
            syncRepository: repo,
            onPullSucceeded: { _ in hookHits.increment() }
        )
        await coord.manualSync()
        XCTAssertEqual(repo.pushCount, 1)
        XCTAssertEqual(repo.pullCount, 1)
        XCTAssertEqual(coord.state, .idle)
        XCTAssertEqual(coord.lastServerTime, "S2")
        XCTAssertEqual(hookHits.value, 1)
    }

    @MainActor
    func test_manualSync_pullFailure_setsFailureState() async {
        let repo = StubSyncRepository()
        repo.pushResponse = SyncPushResponse(accepted: true)
        repo.pullError = APIError.business(code: 50001, message: "服务不可用")
        let coord = SyncCoordinator(syncRepository: repo)
        await coord.manualSync()
        if case .failure(let msg) = coord.state {
            XCTAssertEqual(msg, "服务不可用")
        } else {
            XCTFail("expected .failure, got \(coord.state)")
        }
        XCTAssertEqual(coord.transientMessage, "服务不可用")
    }

    @MainActor
    func test_manualSync_doesNotRunConcurrently() async {
        let repo = StubSyncRepository()
        repo.pullResponse = SyncPullResponse()
        repo.pushResponse = SyncPushResponse(accepted: true)
        repo.artificialDelay = 0.05
        let coord = SyncCoordinator(syncRepository: repo)
        async let a: Void = coord.manualSync()
        async let b: Void = coord.manualSync()
        _ = await (a, b)
        // 第二次 manualSync 见 state == .syncing 时直接返回。
        XCTAssertEqual(repo.pushCount, 1)
        XCTAssertEqual(repo.pullCount, 1)
    }

    @MainActor
    func test_resetForSignOut_clearsStateAndCancelsBootstrap() async {
        let repo = StubSyncRepository()
        repo.bootstrapResponse = SyncPullResponse(serverTime: "S")
        repo.artificialDelay = 0.05
        let coord = SyncCoordinator(syncRepository: repo)
        coord.bootstrapIfNeeded()
        coord.resetForSignOut()
        XCTAssertEqual(coord.state, .idle)
        XCTAssertNil(coord.lastServerTime)
        // 再次 bootstrap 应可触发
        coord.bootstrapIfNeeded()
        await waitForState(coord) { $0.lastServerTime == "S" }
        XCTAssertGreaterThanOrEqual(repo.bootstrapCount, 1)
    }

    // MARK: - helpers

    @MainActor
    private func waitForState(_ coord: SyncCoordinator, _ predicate: @MainActor (SyncCoordinator) -> Bool) async {
        for _ in 0..<200 {
            if predicate(coord) { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("等待 SyncCoordinator 状态超时")
    }
}

private final class StubSyncRepository: SyncRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.sync.repo")
    private var _bootstrapCount = 0
    private var _pullCount = 0
    private var _pushCount = 0
    var bootstrapResponse: SyncPullResponse = SyncPullResponse()
    var pullResponse: SyncPullResponse = SyncPullResponse()
    var pushResponse: SyncPushResponse = SyncPushResponse()
    var pullError: Error? = nil
    var pushError: Error? = nil
    var bootstrapError: Error? = nil
    var artificialDelay: TimeInterval = 0

    var bootstrapCount: Int { queue.sync { _bootstrapCount } }
    var pullCount: Int { queue.sync { _pullCount } }
    var pushCount: Int { queue.sync { _pushCount } }

    func bootstrap() async throws -> SyncPullResponse {
        queue.sync { _bootstrapCount += 1 }
        if artificialDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(artificialDelay * 1_000_000_000))
        }
        if let err = bootstrapError { throw err }
        return bootstrapResponse
    }

    func pull() async throws -> SyncPullResponse {
        queue.sync { _pullCount += 1 }
        if artificialDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(artificialDelay * 1_000_000_000))
        }
        if let err = pullError { throw err }
        return pullResponse
    }

    func push(_ payload: SyncPushRequest) async throws -> SyncPushResponse {
        queue.sync { _pushCount += 1 }
        if artificialDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(artificialDelay * 1_000_000_000))
        }
        if let err = pushError { throw err }
        return pushResponse
    }
}

private final class HitBox: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.hit")
    private var _value = 0
    var value: Int { queue.sync { _value } }
    func increment() { queue.sync { _value += 1 } }
}
