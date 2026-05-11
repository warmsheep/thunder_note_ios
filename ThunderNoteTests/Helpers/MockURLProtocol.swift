import Foundation
@testable import ThunderNote

/// 用于 `APIClient` 测试的 URLProtocol 替身。
/// 用法：在 `XCTestCase.setUp` 中设置 `MockURLProtocol.handler = { request in ... }`。
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    static let queue = DispatchQueue(label: "tn.tests.mockurlprotocol")
    nonisolated(unsafe) private static var _handler: Handler?
    nonisolated(unsafe) private static var _requestLog: [URLRequest] = []

    static var handler: Handler? {
        get { queue.sync { _handler } }
        set { queue.sync { _handler = newValue } }
    }

    static var requestLog: [URLRequest] {
        queue.sync { _requestLog }
    }

    static func reset() {
        queue.sync {
            _handler = nil
            _requestLog = []
        }
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.queue.sync { Self._requestLog.append(request) }
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

/// 简单 ServerConfigStoreProviding 替身。
struct StaticServerConfig: ServerConfigStoreProviding, Sendable {
    let baseURL: URL
    var currentBaseURL: URL { baseURL }
    var displayLabel: String { baseURL.absoluteString }
    var isOfficial: Bool { true }
}

extension HTTPURLResponse {
    static func make(url: URL, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
    }
}
