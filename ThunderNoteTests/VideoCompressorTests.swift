import XCTest
@testable import ThunderNote

final class VideoCompressorTests: XCTestCase {
    func test_compressIfNeeded_returnsOriginalForSmallFile() async throws {
        // 写一个 1KB 的"伪视频"文件——VideoCompressor 不会真去解码它，
        // 只看 size 是否 <= threshold。
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tn-vid-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data(repeating: 0, count: 1024).write(to: tmp)

        let result = try await VideoCompressor.compressIfNeeded(at: tmp)

        XCTAssertEqual(result, tmp, "≤ 5MB 的文件应直接复用原 URL")
    }

    func test_thresholdBytes_is5MB() {
        XCTAssertEqual(VideoCompressor.thresholdBytes, 5 * 1024 * 1024)
    }
}
