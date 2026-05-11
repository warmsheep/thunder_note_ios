import XCTest
@testable import ThunderNote

final class ConversationKeyTests: XCTestCase {
    func test_descriptor_formatsConsistently() {
        XCTAssertEqual(ConversationKey.flashNote(123).descriptor, "flash:123")
        XCTAssertEqual(ConversationKey.flashNote(-1).descriptor, "flash:-1")
        XCTAssertEqual(ConversationKey.peer(456).descriptor, "peer:456")
    }

    func test_isInbox_onlyTrueForInboxId() {
        XCTAssertTrue(ConversationKey.flashNote(-1).isInbox)
        XCTAssertFalse(ConversationKey.flashNote(0).isInbox)
        XCTAssertFalse(ConversationKey.peer(-1).isInbox)
    }

    func test_requestFields_routeByMode() {
        XCTAssertEqual(ConversationKey.flashNote(7).flashNoteIdForRequest, 7)
        XCTAssertNil(ConversationKey.flashNote(7).peerUserIdForRequest)
        XCTAssertEqual(ConversationKey.peer(8).peerUserIdForRequest, 8)
        XCTAssertNil(ConversationKey.peer(8).flashNoteIdForRequest)
    }
}
