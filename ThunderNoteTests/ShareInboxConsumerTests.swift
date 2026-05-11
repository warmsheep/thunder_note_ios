import XCTest
@testable import ThunderNote

final class ShareInboxConsumerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tn.tests.consumer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        try super.tearDownWithError()
    }

    @MainActor
    func test_scan_loadsEntriesFromStore() throws {
        let store = ShareInboxStore(rootURL: tempRoot)!
        try store.append(ShareInboxEntry(kind: .text, text: "alpha"))
        try store.append(ShareInboxEntry(kind: .text, text: "beta"))

        let consumer = ShareInboxConsumer(store: store)
        consumer.scan()

        XCTAssertEqual(consumer.pendingEntries.count, 2)
        XCTAssertEqual(consumer.pendingEntries.map(\.text), ["alpha", "beta"])
    }

    @MainActor
    func test_markConsumed_dropsEntryFromStoreAndMemory() throws {
        let store = ShareInboxStore(rootURL: tempRoot)!
        let entry = ShareInboxEntry(kind: .text, text: "x")
        try store.append(entry)
        let consumer = ShareInboxConsumer(store: store)
        consumer.scan()

        consumer.markConsumed(entry)

        XCTAssertTrue(consumer.pendingEntries.isEmpty)
        XCTAssertTrue(store.allEntries().isEmpty)
    }

    @MainActor
    func test_clearAll_emptiesBothMemoryAndStore() throws {
        let store = ShareInboxStore(rootURL: tempRoot)!
        try store.append(ShareInboxEntry(kind: .text, text: "x"))
        let consumer = ShareInboxConsumer(store: store)
        consumer.scan()

        consumer.clearAll()

        XCTAssertTrue(consumer.pendingEntries.isEmpty)
        XCTAssertTrue(store.allEntries().isEmpty)
    }

    @MainActor
    func test_consumerWithNilStore_returnsEmpty() {
        let consumer = ShareInboxConsumer(store: nil)
        consumer.scan()
        XCTAssertTrue(consumer.pendingEntries.isEmpty)
    }
}
