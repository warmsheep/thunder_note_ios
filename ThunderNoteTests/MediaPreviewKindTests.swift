import XCTest
@testable import ThunderNote

final class MediaPreviewKindTests: XCTestCase {
    func test_resolve_imageVideoMapsDirectly() {
        XCTAssertEqual(MediaPreviewKind.resolve(mediaType: .image), .image)
        XCTAssertEqual(MediaPreviewKind.resolve(mediaType: .video), .video)
    }

    func test_resolve_pdfFromContentTypeAndExtension() {
        XCTAssertEqual(
            MediaPreviewKind.resolve(mediaType: .file, contentType: "application/pdf"),
            .pdf
        )
        XCTAssertEqual(
            MediaPreviewKind.resolve(mediaType: .file, fileName: "report.PDF"),
            .pdf
        )
    }

    func test_resolve_imageExtensionFallback() {
        XCTAssertEqual(
            MediaPreviewKind.resolve(mediaType: .file, fileName: "photo.heic"),
            .image
        )
        XCTAssertEqual(
            MediaPreviewKind.resolve(mediaType: .file, fileName: "snap.jpg"),
            .image
        )
    }

    func test_resolve_videoExtensionFallback() {
        XCTAssertEqual(
            MediaPreviewKind.resolve(mediaType: .file, fileName: "clip.mp4"),
            .video
        )
        XCTAssertEqual(
            MediaPreviewKind.resolve(mediaType: .file, fileName: "movie.MOV"),
            .video
        )
    }

    func test_resolve_unknownFallsBackToOther() {
        XCTAssertEqual(
            MediaPreviewKind.resolve(mediaType: .file, fileName: "data.bin"),
            .other
        )
        XCTAssertEqual(
            MediaPreviewKind.resolve(mediaType: .file),
            .other
        )
    }
}
