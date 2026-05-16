import XCTest
import ZIPFoundation
@testable import ThunderNote

final class EpubDocumentTests: XCTestCase {
    func test_resolve_epubFromContentTypeAndExtension() {
        XCTAssertEqual(
            MediaPreviewKind.resolve(mediaType: .file, contentType: "application/epub+zip"),
            .epub
        )
        XCTAssertEqual(
            MediaPreviewKind.resolve(mediaType: .file, fileName: "book.EPUB"),
            .epub
        )
    }

    func test_prepare_validMinimalEpub_generatesReadableHTML() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let epubURL = root.appendingPathComponent("book.epub")
        try makeEpub(at: epubURL, entries: [
            "META-INF/container.xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OPS/package.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """,
            "OPS/package.opf": """
            <?xml version="1.0" encoding="UTF-8"?>
            <package version="3.0" xmlns="http://www.idpf.org/2007/opf">
              <manifest>
                <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="chapter1"/>
              </spine>
            </package>
            """,
            "OPS/chapter1.xhtml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml">
              <body><h1>第一章</h1><p>闪记 EPUB 正文</p></body>
            </html>
            """
        ])

        let document = try EpubDocument.prepare(epubURL: epubURL)
        let html = try String(contentsOf: document.htmlURL, encoding: .utf8)
        XCTAssertTrue(html.contains("第一章"))
        XCTAssertTrue(html.contains("闪记 EPUB 正文"))
        XCTAssertTrue(document.readAccessURL.path.contains("tn.epub"))
    }

    func test_prepare_rejectsUnsafeZipEntryPath() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let epubURL = root.appendingPathComponent("evil.epub")
        try makeEpub(at: epubURL, entries: [
            "../evil.txt": "owned"
        ])

        XCTAssertThrowsError(try EpubDocument.prepare(epubURL: epubURL)) { error in
            guard case EpubDocumentError.unsafePath = error else {
                return XCTFail("expected unsafePath, got \(error)")
            }
        }
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tn-epub-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeEpub(at url: URL, entries: [String: String]) throws {
        let archive = try Archive(url: url, accessMode: .create)
        for (path, contents) in entries {
            let data = Data(contents.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), provider: { position, size -> Data in
                let start = Int(position)
                return data.subdata(in: start..<(start + size))
            })
        }
    }
}
