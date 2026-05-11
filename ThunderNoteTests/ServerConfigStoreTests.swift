import XCTest
@testable import ThunderNote

final class ServerConfigStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "ServerConfigStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func test_defaultModeIsOfficial() {
        let store = ServerConfigStore(userDefaults: defaults)
        XCTAssertTrue(store.isOfficial)
        XCTAssertEqual(store.currentBaseURL, ServerConfigStore.officialBaseURL)
    }

    func test_useSelfHosted_persistsNormalizedURL() throws {
        let store = ServerConfigStore(userDefaults: defaults)
        try store.useSelfHosted(rawURL: "my-server.com:8080")
        XCTAssertFalse(store.isOfficial)
        XCTAssertEqual(store.currentBaseURL.absoluteString, "https://my-server.com:8080/")
    }

    func test_useOfficial_resetsSelfHostedURL() throws {
        let store = ServerConfigStore(userDefaults: defaults)
        try store.useSelfHosted(rawURL: "https://my-server.com")
        store.useOfficial()
        XCTAssertTrue(store.isOfficial)
        XCTAssertEqual(store.currentBaseURL, ServerConfigStore.officialBaseURL)
    }

    func test_normalize_rejectsBadInput() {
        XCTAssertThrowsError(try ServerConfigStore.normalize("")) { error in
            XCTAssertEqual(error as? ServerConfigStore.ConfigError, .empty)
        }
        XCTAssertThrowsError(try ServerConfigStore.normalize("ftp://example.com")) { error in
            XCTAssertEqual(error as? ServerConfigStore.ConfigError, .invalidScheme)
        }
        XCTAssertThrowsError(try ServerConfigStore.normalize("https://example.com/api/v1")) { error in
            XCTAssertEqual(error as? ServerConfigStore.ConfigError, .extraPath)
        }
    }

    func test_normalize_acceptsHttpsAndHttp() throws {
        XCTAssertEqual(try ServerConfigStore.normalize("https://example.com").absoluteString, "https://example.com/")
        XCTAssertEqual(try ServerConfigStore.normalize("http://10.0.0.1:9000").absoluteString, "http://10.0.0.1:9000/")
    }

    func test_normalize_addsHttpsWhenSchemeMissing() throws {
        XCTAssertEqual(try ServerConfigStore.normalize("example.com").absoluteString, "https://example.com/")
    }
}
