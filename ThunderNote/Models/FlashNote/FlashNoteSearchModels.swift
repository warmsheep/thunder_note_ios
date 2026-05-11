import Foundation

/// D2-I2-15 闪记列表搜索请求 / 响应模型。
/// 与服务端 `FlashNoteController.search` + Android `FlashNoteSearchRequest /
/// FlashNoteSearchResponse / FlashNoteSearchResult / MatchedMessageInfo` 对齐：
/// 顶层 `data: { noteNameMatched: [...], messageContentMatched: [...] }`，
/// 每项 `{ flashNote, matchedMessages: [{ messageId, snippet, contextMessages }], noteMatched }`。

public struct FlashNoteSearchRequest: Encodable, Sendable {
    public let query: String

    public init(query: String) {
        self.query = query
    }
}

public struct FlashNoteSearchResponse: Decodable, Sendable, Equatable {
    public let noteNameMatched: [FlashNoteSearchResult]
    public let messageContentMatched: [FlashNoteSearchResult]

    public init(
        noteNameMatched: [FlashNoteSearchResult],
        messageContentMatched: [FlashNoteSearchResult]
    ) {
        self.noteNameMatched = noteNameMatched
        self.messageContentMatched = messageContentMatched
    }

    private enum CodingKeys: String, CodingKey {
        case noteNameMatched
        case messageContentMatched
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 后端在没有命中时可能不返回字段，统一兜底为空数组。
        self.noteNameMatched = try container.decodeIfPresent([FlashNoteSearchResult].self, forKey: .noteNameMatched) ?? []
        self.messageContentMatched = try container.decodeIfPresent([FlashNoteSearchResult].self, forKey: .messageContentMatched) ?? []
    }
}

public struct FlashNoteSearchResult: Decodable, Sendable, Equatable {
    public let flashNote: FlashNote
    public let matchedMessages: [MatchedMessageInfo]
    public let noteMatched: Bool

    public init(flashNote: FlashNote, matchedMessages: [MatchedMessageInfo], noteMatched: Bool) {
        self.flashNote = flashNote
        self.matchedMessages = matchedMessages
        self.noteMatched = noteMatched
    }

    private enum CodingKeys: String, CodingKey {
        case flashNote
        case matchedMessages
        case noteMatched
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.flashNote = try container.decode(FlashNote.self, forKey: .flashNote)
        self.matchedMessages = try container.decodeIfPresent([MatchedMessageInfo].self, forKey: .matchedMessages) ?? []
        self.noteMatched = try container.decodeIfPresent(Bool.self, forKey: .noteMatched) ?? false
    }
}

public struct MatchedMessageInfo: Decodable, Sendable, Equatable, Identifiable {
    public let messageId: Int64
    public let snippet: String?
    public let contextMessages: [Message]

    public var id: Int64 { messageId }

    public init(messageId: Int64, snippet: String?, contextMessages: [Message]) {
        self.messageId = messageId
        self.snippet = snippet
        self.contextMessages = contextMessages
    }

    private enum CodingKeys: String, CodingKey {
        case messageId
        case snippet
        case contextMessages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.messageId = try container.decode(Int64.self, forKey: .messageId)
        self.snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        self.contextMessages = try container.decodeIfPresent([Message].self, forKey: .contextMessages) ?? []
    }
}
