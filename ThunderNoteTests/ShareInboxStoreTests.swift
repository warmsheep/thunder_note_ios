import XCTest
@testable import ThunderNote

final class ShareInboxStoreTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tn.tests.shareinbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        try super.tearDownWithError()
    }

    func test_appendThenAllEntries_returnsInsertedEntry() throws {
        let store = ShareInboxStore(rootURL: tempRoot)!
        let entry = ShareInboxEntry(kind: .text, text: "hello world")
        try store.append(entry)

        let all = store.allEntries()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].text, "hello world")
        XCTAssertEqual(all[0].kind, .text)
    }

    func test_remove_dropsEntry() throws {
        let store = ShareInboxStore(rootURL: tempRoot)!
        let a = ShareInboxEntry(kind: .text, text: "a")
        let b = ShareInboxEntry(kind: .text, text: "b")
        try store.append(a)
        try store.append(b)

        try store.remove(id: a.id)

        let remaining = store.allEntries()
        XCTAssertEqual(remaining.map(\.text), ["b"])
    }

    func test_clearAll_emptiesEntriesAndAttachments() throws {
        let store = ShareInboxStore(rootURL: tempRoot)!
        try store.append(ShareInboxEntry(kind: .text, text: "x"))

        // 模拟一份附件
        let source = tempRoot.appendingPathComponent("sample.txt")
        try Data("payload".utf8).write(to: source)
        let relative = try store.storeAttachment(sourceURL: source, suggestedName: "sample.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.resolveAttachmentURL(relativePath: relative).path))

        try store.clearAll()
        XCTAssertTrue(store.allEntries().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.resolveAttachmentURL(relativePath: relative).path))
    }

    func test_storeAttachment_copiesFileWithStableRelativePath() throws {
        let store = ShareInboxStore(rootURL: tempRoot)!
        let source = tempRoot.appendingPathComponent("foo bar.png")
        try Data("png".utf8).write(to: source)

        let rel = try store.storeAttachment(sourceURL: source, suggestedName: "foo bar.png")

        let resolved = store.resolveAttachmentURL(relativePath: rel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path))
        XCTAssertTrue(rel.contains("foo bar.png"), "保留原始名便于主 App 展示")
    }

    func test_persistence_acrossInstances() throws {
        let store1 = ShareInboxStore(rootURL: tempRoot)!
        try store1.append(ShareInboxEntry(kind: .text, text: "persisted"))

        let store2 = ShareInboxStore(rootURL: tempRoot)!
        XCTAssertEqual(store2.allEntries().count, 1)
        XCTAssertEqual(store2.allEntries().first?.text, "persisted")
    }
}
