import XCTest
@testable import ThunderNote

final class CardPayloadTests: XCTestCase {

    func test_decode_serverPayload_mapsCardTypeAndItemKeys() throws {
        let json = """
        {
          "cardType": "MESSAGE_COLLECTION",
          "title": "标题",
          "summary": "hi 等2条消息",
          "items": [
            {
              "originalMsgId": 11,
              "type": "TEXT",
              "content": "hi",
              "senderId": 1,
              "role": "user"
            },
            {
              "originalMsgId": 12,
              "type": "image",
              "url": "1/abc.jpg",
              "thumbnailUrl": "1/abc.thumb.jpg",
              "fileName": "abc.jpg",
              "fileSize": 1024,
              "senderId": 1,
              "role": "user"
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let payload = try JSONDecoder().decode(CardPayload.self, from: data)
        XCTAssertEqual(payload.cardType, "MESSAGE_COLLECTION")
        XCTAssertEqual(payload.title, "标题")
        XCTAssertEqual(payload.items?.count, 2)

        let textItem = payload.items![0]
        XCTAssertEqual(textItem.originalMsgId, 11)
        XCTAssertEqual(textItem.mediaType, "TEXT")
        XCTAssertEqual(textItem.resolvedMediaType, .text)
        XCTAssertEqual(textItem.content, "hi")
        XCTAssertEqual(textItem.role, "user")

        let imgItem = payload.items![1]
        XCTAssertEqual(imgItem.mediaType, "image")
        XCTAssertEqual(imgItem.mediaUrl, "1/abc.jpg")
        XCTAssertEqual(imgItem.thumbnailUrl, "1/abc.thumb.jpg")
        XCTAssertEqual(imgItem.fileName, "abc.jpg")
        XCTAssertEqual(imgItem.fileSize, 1024)
        XCTAssertEqual(imgItem.resolvedMediaType, .image)
    }

    func test_resolvedMediaType_handlesLowerAndUpperCase() {
        let upper = CardItem(mediaType: "IMAGE")
        XCTAssertEqual(upper.resolvedMediaType, .image)
        let lower = CardItem(mediaType: "image")
        XCTAssertEqual(lower.resolvedMediaType, .image)
        let video = CardItem(mediaType: "video")
        XCTAssertEqual(video.resolvedMediaType, .video)
        let file = CardItem(mediaType: "file")
        XCTAssertEqual(file.resolvedMediaType, .file)
        let unknown = CardItem(mediaType: "weird")
        XCTAssertEqual(unknown.resolvedMediaType, .file)
    }

    func test_message_decode_carriesPayloadThroughMessage() throws {
        let json = """
        {
          "id": 99,
          "senderId": 1,
          "receiverId": 1,
          "flashNoteId": 2,
          "mediaType": "COMPOSITE",
          "content": "卡片",
          "createdAt": "2026-05-11T10:02:00",
          "payload": {
            "cardType": "COMPOSITE_MEDIA",
            "title": "卡片",
            "items": [
              {"type": "image", "url": "1/abc.jpg", "thumbnailUrl": "1/abc.thumb.jpg"}
            ]
          }
        }
        """
        let msg = try JSONDecoder().decode(Message.self, from: Data(json.utf8))
        XCTAssertEqual(msg.id, 99)
        XCTAssertEqual(msg.payload?.cardType, "COMPOSITE_MEDIA")
        XCTAssertEqual(msg.payload?.items?.first?.mediaUrl, "1/abc.jpg")
    }
}
