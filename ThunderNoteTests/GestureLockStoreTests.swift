import XCTest
@testable import ThunderNote

/// 覆盖 `KeychainGestureLockStore` 的 UserDefaults 兜底路径。
///
/// 真机带签名场景走 Keychain，无法在 host App 单测里稳定触发 `errSecMissingEntitlement`。
/// 这里通过把 `fallbackEnabledKey` 预置到隔离的 UserDefaults suite，让 store 启动时直接进入兜底路径，
/// 验证 set / isEnabled / verify / clear / 多用户隔离 / hash 一致性这一组语义在兜底下与 Keychain 完全等价。
final class GestureLockStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "tn.tests.gesture.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    private func makeFallbackStore() -> KeychainGestureLockStore {
        // 预置兜底标记，模拟"上次运行 Keychain 不可用，已经走过兜底"。
        defaults.set(true, forKey: "tn.gesture.fallback.enabled")
        return KeychainGestureLockStore(
            service: "com.flashnote.ios.gesture.tests.\(suiteName!)",
            fallbackDefaults: defaults
        )
    }

    func test_fallback_isEnabled_initialFalse() {
        let store = makeFallbackStore()
        XCTAssertFalse(store.isEnabled(for: "alice"))
        XCTAssertFalse(store.isEnabled(for: ""))
    }

    func test_fallback_setVerify_roundTrip() {
        let store = makeFallbackStore()
        store.set(password: "12580", for: "alice")
        XCTAssertTrue(store.isEnabled(for: "alice"))
        XCTAssertTrue(store.verify(password: "12580", for: "alice"))
        XCTAssertFalse(store.verify(password: "00000", for: "alice"))
    }

    func test_fallback_clear_disablesIsEnabled() {
        let store = makeFallbackStore()
        store.set(password: "12580", for: "alice")
        XCTAssertTrue(store.isEnabled(for: "alice"))

        store.clear(for: "alice")
        XCTAssertFalse(store.isEnabled(for: "alice"))
        XCTAssertFalse(store.verify(password: "12580", for: "alice"))
    }

    func test_fallback_perUserIsolation() {
        let store = makeFallbackStore()
        store.set(password: "12580", for: "alice")
        store.set(password: "67890", for: "bob")

        XCTAssertTrue(store.verify(password: "12580", for: "alice"))
        XCTAssertFalse(store.verify(password: "12580", for: "bob"))
        XCTAssertTrue(store.verify(password: "67890", for: "bob"))
        XCTAssertFalse(store.verify(password: "67890", for: "alice"))

        store.clear(for: "alice")
        XCTAssertFalse(store.isEnabled(for: "alice"))
        // bob 的不能被 alice 的 clear 顺手清掉
        XCTAssertTrue(store.isEnabled(for: "bob"))
        XCTAssertTrue(store.verify(password: "67890", for: "bob"))
    }

    func test_fallback_hashPassword_isStableAndUserScoped() {
        let store = makeFallbackStore()
        let h1 = store.hashPassword("12580", for: "alice")
        let h2 = store.hashPassword("12580", for: "alice")
        let h3 = store.hashPassword("12580", for: "bob")

        XCTAssertEqual(h1, h2, "同一 (password, username) 必须稳定")
        XCTAssertNotEqual(h1, h3, "不同 username 的 hash 不能相同（用户隔离）")
        XCTAssertFalse(h1.isEmpty)
    }

    func test_fallback_persistsAcrossInstances_sameDefaults() {
        let storeA = makeFallbackStore()
        storeA.set(password: "12580", for: "alice")

        // 同一份 UserDefaults，新实例应当继续走兜底并读到上一实例写入的密文。
        let storeB = KeychainGestureLockStore(
            service: "com.flashnote.ios.gesture.tests.\(suiteName!)",
            fallbackDefaults: defaults
        )
        XCTAssertTrue(storeB.isEnabled(for: "alice"))
        XCTAssertTrue(storeB.verify(password: "12580", for: "alice"))
    }

    func test_fallback_setEmptyPasswordOrUsername_isNoop() {
        let store = makeFallbackStore()
        store.set(password: "", for: "alice")
        store.set(password: "12580", for: "")
        XCTAssertFalse(store.isEnabled(for: "alice"))
        XCTAssertFalse(store.isEnabled(for: ""))
    }
}
