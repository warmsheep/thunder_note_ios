import XCTest
@testable import ThunderNote

final class MessageMediaPreloaderTests: XCTestCase {
    func test_preload_triggersDownloadForRecentImageAndVideoOnly() async {
        let stubFile = PreloaderStubFileRepo()
        let preloader = MessageMediaPreloader(fileRepository: stubFile)

        let items: [ChatMessageItem] = [
            makeItem(id: 1, mediaType: "TEXT", thumb: nil, media: nil),
            makeItem(id: 2, mediaType: "IMAGE", thumb: "img/thumb-2.jpg", media: nil),
            makeItem(id: 3, mediaType: "VIDEO", thumb: "vid/thumb-3.jpg", media: "vid/full-3.mp4"),
            makeItem(id: 4, mediaType: "FILE", thumb: nil, media: "files/x.pdf"),
            makeItem(id: 5, mediaType: "IMAGE", thumb: nil, media: "img/full-5.jpg"),
        ]

        await preloader.preload(items: items, limit: 5)

        let downloaded = Set(stubFile.downloadedObjectNames)
        // 仅 image / video 走预加载；text / file 不参与
        XCTAssertTrue(downloaded.contains("img/thumb-2.jpg"))
        XCTAssertTrue(downloaded.contains("vid/thumb-3.jpg"))
        XCTAssertTrue(downloaded.contains("img/full-5.jpg"), "图片缺 thumb 时回退到原图")
        XCTAssertFalse(downloaded.contains("vid/full-3.mp4"), "视频只预加载缩略图，不预加载源文件")
        XCTAssertFalse(downloaded.contains("files/x.pdf"))
    }

    private func makeItem(id: Int64, mediaType: String, thumb: String?, media: String?) -> ChatMessageItem {
        ChatMessageItem(
            clientRequestId: nil,
            remoteId: id,
            status: .sent,
            message: Message(
                id: id,
                content: nil,
                mediaType: mediaType,
                mediaUrl: media,
                thumbnailUrl: thumb
            )
        )
    }
}

private final class PreloaderStubFileRepo: FileRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.preload.file")
    private var _downloads: [String] = []

    var downloadedObjectNames: [String] { queue.sync { _downloads } }

    func upload(
        fileURL: URL,
        mimeType: String,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> FileUploadResult {
        FileUploadResult(objectName: "ignored", originalFilename: nil)
    }

    func resolveDownloadURL(objectName: String?) -> URL? { nil }

    func download(objectName: String) async throws -> URL {
        queue.sync { _downloads.append(objectName) }
        return URL(fileURLWithPath: "/tmp/\(objectName.hashValue)")
    }
}
