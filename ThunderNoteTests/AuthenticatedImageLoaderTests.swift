import XCTest
import UIKit
@testable import ThunderNote

final class AuthenticatedImageLoaderTests: XCTestCase {
    private var session: URLSession!
    private let url = URL(string: "https://example.com/api/files/download?objectName=avatar")!

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

    func test_load_attachesAuthorizationHeader() async throws {
        let probe = AuthHeaderProbe()
        MockURLProtocol.handler = { request in
            probe.set(request.value(forHTTPHeaderField: "Authorization"))
            return (HTTPURLResponse.make(url: request.url!, status: 200), pngOnePixelData())
        }
        let loader = AuthenticatedImageLoader(
            session: session,
            tokenAccessor: StaticTokenAccessor(access: "MY_TOKEN")
        )
        _ = try await loader.load(url: url)
        XCTAssertEqual(probe.value, "Bearer MY_TOKEN")
    }

    func test_load_cachesResultForSubsequentCalls() async throws {
        let counter = HitCounter()
        MockURLProtocol.handler = { request in
            counter.increment()
            return (HTTPURLResponse.make(url: request.url!, status: 200), pngOnePixelData())
        }
        let loader = AuthenticatedImageLoader(
            session: session,
            tokenAccessor: StaticTokenAccessor(access: "x")
        )
        _ = try await loader.load(url: url)
        _ = try await loader.load(url: url)
        XCTAssertEqual(counter.value, 1, "第二次应命中缓存而不再发请求")
        XCTAssertNotNil(loader.cached(for: url))
    }

    func test_load_non200ThrowsHttp() async {
        MockURLProtocol.handler = { request in
            return (HTTPURLResponse.make(url: request.url!, status: 401), Data())
        }
        let loader = AuthenticatedImageLoader(
            session: session,
            tokenAccessor: StaticTokenAccessor(access: "x")
        )
        do {
            _ = try await loader.load(url: url)
            XCTFail("应该抛 http 错误")
        } catch let error as AuthenticatedImageLoader.LoadError {
            XCTAssertEqual(error, .http(status: 401))
        } catch {
            XCTFail("应该抛 LoadError.http，但抛了 \(error)")
        }
    }
}

private func pngOnePixelData() -> Data {
    // 1x1 transparent PNG
    let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    return Data(base64Encoded: base64)!
}

/// 用 NSLock 包装的线程安全计数器（替代 `var hitCount = 0` + 闭包捕获）。
private final class HitCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0
    func increment() {
        lock.lock(); defer { lock.unlock() }
        _value += 1
    }
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
}

/// 同上：线程安全保存 Authorization header。
private final class AuthHeaderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?
    func set(_ next: String?) {
        lock.lock(); defer { lock.unlock() }
        _value = next
    }
    var value: String? {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
}

/// 给单测用的静态 token accessor，避免依赖真实 Keychain。
private final class StaticTokenAccessor: APIClient.TokenAccessor, @unchecked Sendable {
    let access: String?
    let refresh: String?
    init(access: String?, refresh: String? = "R") {
        self.access = access
        self.refresh = refresh
    }
    func currentAccessToken() async -> String? { access }
    func currentRefreshToken() async -> String? { refresh }
    func saveSession(_ response: LoginResponse) async {}
    func clearSession() async {}
}
