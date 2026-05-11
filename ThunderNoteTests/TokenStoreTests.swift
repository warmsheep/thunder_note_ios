import XCTest
@testable import ThunderNote

/// `KeychainTokenStore` 的真实 Keychain 行为由系统服务保证，集成验证放在 host App 启动后。
/// 这里覆盖与 `TokenStoring` 协议一致的 `InMemoryTokenStore`，确保接口契约本身正确。
final class TokenStoreTests: XCTestCase {
    func test_save_storesTokensAndUserMeta() {
        let store = InMemoryTokenStore()
        let response = LoginResponse(
            accessToken: "A",
            refreshToken: "R",
            tokenType: "Bearer",
            expiresIn: 3600000,
            user: User(id: 42, username: "alice")
        )
        store.save(loginResponse: response)
        XCTAssertEqual(store.loadAccessToken(), "A")
        XCTAssertEqual(store.loadRefreshToken(), "R")
        XCTAssertEqual(store.loadUserId(), 42)
        XCTAssertEqual(store.loadUsername(), "alice")
        XCTAssertNotNil(store.loadAccessTokenExpiresAt())
    }

    func test_clear_removesAllValues() {
        let store = InMemoryTokenStore()
        store.save(loginResponse: LoginResponse(
            accessToken: "A",
            refreshToken: "R",
            tokenType: "Bearer",
            expiresIn: 3600000,
            user: User(id: 1, username: "alice")
        ))
        XCTAssertTrue(store.hasAccessToken)
        store.clear()
        XCTAssertFalse(store.hasAccessToken)
        XCTAssertNil(store.loadAccessToken())
        XCTAssertNil(store.loadRefreshToken())
        XCTAssertNil(store.loadUserId())
        XCTAssertNil(store.loadUsername())
    }
}
