import XCTest
@testable import ThunderNote

final class ChatScrollAnchorStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "tn.tests.scrollAnchor"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_setAndGetAnchor_returnsValueForSameKey() {
        let store = ChatScrollAnchorStore(defaults: defaults)
        let key: ConversationKey = .flashNote(42)

        XCTAssertNil(store.anchor(for: key))
        store.setAnchor(123, for: key)
        XCTAssertEqual(store.anchor(for: key), 123)

        // 不同 key 不应串扰
        let other: ConversationKey = .peer(99)
        XCTAssertNil(store.anchor(for: other))
    }

    func test_setAnchor_zeroOrNegative_clearsValue() {
        let store = ChatScrollAnchorStore(defaults: defaults)
        let key: ConversationKey = .flashNote(1)
        store.setAnchor(7, for: key)
        XCTAssertEqual(store.anchor(for: key), 7)
        store.setAnchor(0, for: key)
        XCTAssertNil(store.anchor(for: key))
    }

    func test_clearAnchor_removesValue() {
        let store = ChatScrollAnchorStore(defaults: defaults)
        let key: ConversationKey = .peer(5)
        store.setAnchor(50, for: key)
        store.clearAnchor(for: key)
        XCTAssertNil(store.anchor(for: key))
    }

    func test_clearAll_removesAllPrefixedKeys() {
        let store = ChatScrollAnchorStore(defaults: defaults)
        store.setAnchor(1, for: .flashNote(1))
        store.setAnchor(2, for: .peer(2))
        XCTAssertEqual(store.anchor(for: .flashNote(1)), 1)
        XCTAssertEqual(store.anchor(for: .peer(2)), 2)
        store.clearAll()
        XCTAssertNil(store.anchor(for: .flashNote(1)))
        XCTAssertNil(store.anchor(for: .peer(2)))
    }
}
