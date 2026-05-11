import XCTest
@testable import ThunderNote

final class ShareInboxEntryTests: XCTestCase {
    func test_isText_onlyTrueForTextKind() {
        XCTAssertTrue(ShareInboxEntry(kind: .text, text: "x").isText)
        XCTAssertFalse(ShareInboxEntry(kind: .image, fileName: "x").isText)
        XCTAssertFalse(ShareInboxEntry(kind: .video, fileName: "x").isText)
        XCTAssertFalse(ShareInboxEntry(kind: .file, fileName: "x").isText)
    }

    func test_previewLabel_describesAttachment() {
        XCTAssertEqual(ShareInboxEntry(kind: .text, text: "hi").previewLabel(), "hi")
        XCTAssertEqual(ShareInboxEntry(kind: .image, fileName: "a.jpg").previewLabel(), "[图片] a.jpg")
        XCTAssertEqual(ShareInboxEntry(kind: .video, fileName: "v.mp4").previewLabel(), "[视频] v.mp4")
        XCTAssertEqual(ShareInboxEntry(kind: .file, fileName: "spec.pdf").previewLabel(), "[文件] spec.pdf")
    }

    func test_codable_roundtrip() throws {
        let original = ShareInboxEntry(
            kind: .file,
            text: nil,
            relativeFilePath: "abc/def.bin",
            fileName: "def.bin",
            fileSize: 1024
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ShareInboxEntry.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
