import XCTest
@testable import ThunderNote

final class RefreshActorTests: XCTestCase {
    /// 并发 N 个 refresh() 应只触发 1 次 performer 调用。
    func test_concurrentRefresh_dedupesToSingleNetworkCall() async throws {
        let counter = Counter()
        let actor = RefreshActor {
            await counter.increment()
            // 模拟一次网络刷新耗时
            try? await Task.sleep(nanoseconds: 50_000_000)
            return LoginResponse(
                accessToken: "NEW",
                refreshToken: "REF",
                tokenType: "Bearer",
                expiresIn: 3600000,
                user: User(id: 1, username: "alice")
            )
        }

        try await withThrowingTaskGroup(of: LoginResponse.self) { group in
            for _ in 0..<10 {
                group.addTask { try await actor.refresh() }
            }
            var count = 0
            for try await _ in group { count += 1 }
            XCTAssertEqual(count, 10)
        }
        let invocations = await counter.value
        XCTAssertEqual(invocations, 1, "并发 10 次 refresh 应仅触发 1 次实际请求")
    }

    /// 第一次刷新结束后，新一次 refresh() 应再次触发 performer。
    func test_sequentialRefresh_reinvokesPerformer() async throws {
        let counter = Counter()
        let actor = RefreshActor {
            await counter.increment()
            return LoginResponse(
                accessToken: "T",
                refreshToken: "R",
                tokenType: "Bearer",
                expiresIn: 3600000,
                user: User(id: 1, username: "alice")
            )
        }
        _ = try await actor.refresh()
        _ = try await actor.refresh()
        let invocations = await counter.value
        XCTAssertEqual(invocations, 2)
    }

    /// performer 抛错时，refresh() 直接向调用方传播错误。
    func test_refresh_propagatesError() async {
        struct Boom: Error {}
        let actor = RefreshActor { throw Boom() }
        do {
            _ = try await actor.refresh()
            XCTFail("应抛错")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }
}

private actor Counter {
    private var counter = 0
    func increment() { counter += 1 }
    var value: Int { counter }
}
