import XCTest
@testable import ThunderNote

/// D2-I7-04 ConversationKeyResolver 与 Android `ConversationKeyUtil` 行为对齐的单测。
final class ConversationKeyResolverTests: XCTestCase {

    func test_forFlashNote_isIdentity() {
        XCTAssertEqual(ConversationKeyResolver.forFlashNote(7), 7)
        XCTAssertEqual(ConversationKeyResolver.forFlashNote(-1), -1) // 收集箱
    }

    func test_forContact_usesContactKeyBaseMinusAbsPeer() {
        XCTAssertEqual(ConversationKeyResolver.forContact(42), -1_000_000_042)
        XCTAssertEqual(ConversationKeyResolver.forContact(-99), -1_000_000_099)
        XCTAssertEqual(ConversationKeyResolver.forContact(1), -1_000_000_001)
    }

    func test_resolve_peerWins_overFlashNote() {
        XCTAssertEqual(
            ConversationKeyResolver.resolve(flashNoteId: 7, peerUserId: 42),
            ConversationKeyResolver.forContact(42)
        )
    }

    func test_resolve_flashNoteWhenPeerNilOrZero() {
        XCTAssertEqual(
            ConversationKeyResolver.resolve(flashNoteId: 7, peerUserId: nil),
            7
        )
        XCTAssertEqual(
            ConversationKeyResolver.resolve(flashNoteId: 7, peerUserId: 0),
            7
        )
    }

    func test_resolve_returnsNilWhenBothMissing() {
        XCTAssertNil(ConversationKeyResolver.resolve(flashNoteId: nil, peerUserId: nil))
        XCTAssertNil(ConversationKeyResolver.resolve(flashNoteId: 0, peerUserId: 0))
    }

    func test_resolveForMessage_usesReceiverIdAsPeer() {
        let m = Message(senderId: 1, receiverId: 42, flashNoteId: nil)
        XCTAssertEqual(
            ConversationKeyResolver.resolveForMessage(m, currentUserId: 1),
            ConversationKeyResolver.forContact(42)
        )
    }

    func test_resolveForMessage_swapsToSenderWhenSelfIsReceiver() {
        // currentUserId == receiverId（自己是收方），需要从 senderId 反推 peer
        let m = Message(senderId: 99, receiverId: 1, flashNoteId: nil)
        XCTAssertEqual(
            ConversationKeyResolver.resolveForMessage(m, currentUserId: 1),
            ConversationKeyResolver.forContact(99)
        )
    }

    func test_resolveForMessage_prefersFlashNote() {
        let m = Message(senderId: 1, receiverId: 0, flashNoteId: 7)
        XCTAssertEqual(
            ConversationKeyResolver.resolveForMessage(m, currentUserId: 1),
            7
        )
    }

    func test_conversationKey_persistenceKeyMatchesResolver() {
        XCTAssertEqual(ConversationKey.flashNote(7).persistenceKey, 7)
        XCTAssertEqual(ConversationKey.peer(42).persistenceKey, ConversationKeyResolver.forContact(42))
    }
}
