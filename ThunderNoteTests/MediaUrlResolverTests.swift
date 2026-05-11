import XCTest
@testable import ThunderNote

final class MediaUrlResolverTests: XCTestCase {
    func test_resolve_returnsNilForNilOrEmpty() {
        let resolver = MediaUrlResolver(
            serverConfigStore: StaticServerConfig(baseURL: URL(string: "https://example.com/")!)
        )
        XCTAssertNil(resolver.resolve(nil))
        XCTAssertNil(resolver.resolve(""))
    }

    func test_resolve_returnsAbsoluteUrlAsIs() {
        let resolver = MediaUrlResolver(
            serverConfigStore: StaticServerConfig(baseURL: URL(string: "https://example.com/")!)
        )
        let absolute = "https://cdn.example.com/foo.jpg"
        XCTAssertEqual(resolver.resolve(absolute)?.absoluteString, absolute)
    }

    func test_resolve_builtsDownloadUrlForRelativeObjectName() {
        let resolver = MediaUrlResolver(
            serverConfigStore: StaticServerConfig(baseURL: URL(string: "https://example.com/")!)
        )
        let url = resolver.resolve("flashnote/2026/05/abc.jpg")
        XCTAssertEqual(url?.path, "/api/files/download")
        XCTAssertTrue(url?.query?.contains("objectName=flashnote/2026/05/abc.jpg") == true
                      || url?.query?.contains("objectName=flashnote%2F2026%2F05%2Fabc.jpg") == true)
    }

    func test_resolve_appendsToBaseWithPath() {
        let resolver = MediaUrlResolver(
            serverConfigStore: StaticServerConfig(baseURL: URL(string: "https://api.example.com:8080/")!)
        )
        let url = resolver.resolve("a/b.jpg")
        XCTAssertEqual(url?.host, "api.example.com")
        XCTAssertEqual(url?.port, 8080)
        XCTAssertTrue(url?.path == "/api/files/download")
    }
}
