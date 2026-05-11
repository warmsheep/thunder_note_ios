import Foundation

/// D2-I7 同步主链 DTO，与服务端 `SyncPullRequest / SyncPushRequest / SyncServiceImpl` + Android
/// `SyncPullRequest / SyncPushRequest / SyncRepositoryImpl` 完全对齐。

// MARK: - Pull

/// `POST /api/sync/pull` 请求体。`lastMessageCreatedAt` 为 LocalDateTime 字符串；
/// 首次 pull 或重置后传 `nil`，服务端返回全量消息。
public struct SyncPullRequest: Encodable, Sendable {
    public let lastMessageCreatedAt: String?

    public init(lastMessageCreatedAt: String?) {
        self.lastMessageCreatedAt = lastMessageCreatedAt
    }
}

/// `POST /api/sync/bootstrap` 与 `/api/sync/pull` 都返回这个 shape。`bootstrap=true` 时只是
/// 标记本次是冷启动 bootstrap。
public struct SyncPullResponse: Decodable, Sendable {
    public let profile: UserProfile?
    public let notes: [FlashNote]
    public let collections: [Collection]
    public let messages: [Message]
    public let favorites: [FavoriteItem]
    public let serverTime: String?
    public let bootstrap: Bool?

    public init(
        profile: UserProfile? = nil,
        notes: [FlashNote] = [],
        collections: [Collection] = [],
        messages: [Message] = [],
        favorites: [FavoriteItem] = [],
        serverTime: String? = nil,
        bootstrap: Bool? = nil
    ) {
        self.profile = profile
        self.notes = notes
        self.collections = collections
        self.messages = messages
        self.favorites = favorites
        self.serverTime = serverTime
        self.bootstrap = bootstrap
    }

    private enum CodingKeys: String, CodingKey {
        case profile, notes, collections, messages, favorites, serverTime, bootstrap
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.profile = try container.decodeIfPresent(UserProfile.self, forKey: .profile)
        self.notes = try container.decodeIfPresent([FlashNote].self, forKey: .notes) ?? []
        self.collections = try container.decodeIfPresent([Collection].self, forKey: .collections) ?? []
        self.messages = try container.decodeIfPresent([Message].self, forKey: .messages) ?? []
        self.favorites = try container.decodeIfPresent([FavoriteItem].self, forKey: .favorites) ?? []
        self.serverTime = try container.decodeIfPresent(String.self, forKey: .serverTime)
        self.bootstrap = try container.decodeIfPresent(Bool.self, forKey: .bootstrap)
    }

    /// 最大 `createdAt`（Lexicographic 字典序对 LocalDateTime ISO8601 安全）。
    /// 用于推进 `sync_meta.last_message_created_at`。
    public var maxMessageCreatedAt: String? {
        messages.compactMap { $0.createdAt }.max()
    }
}

// MARK: - Push

/// `POST /api/sync/push` 请求体。与服务端 `SyncPushRequest` 字段一一对应。
/// 当前阶段 iOS 端 push 主要用于幂等回放 PendingMessage；notes / collections / favorites
/// 在 PendingChain 完整搭起来之前先发空数组。
public struct SyncPushRequest: Encodable, Sendable {
    public let notes: [NotePushDTO]
    public let collections: [CollectionPushDTO]
    public let messages: [MessagePushDTO]
    public let favorites: [FavoritePushDTO]

    public init(
        notes: [NotePushDTO] = [],
        collections: [CollectionPushDTO] = [],
        messages: [MessagePushDTO] = [],
        favorites: [FavoritePushDTO] = []
    ) {
        self.notes = notes
        self.collections = collections
        self.messages = messages
        self.favorites = favorites
    }

    public struct NotePushDTO: Encodable, Sendable {
        public let id: Int64
        public let title: String?
        public let content: String?
        public let tags: String?
        public let deleted: Bool?

        public init(id: Int64, title: String? = nil, content: String? = nil, tags: String? = nil, deleted: Bool? = nil) {
            self.id = id
            self.title = title
            self.content = content
            self.tags = tags
            self.deleted = deleted
        }
    }

    public struct CollectionPushDTO: Encodable, Sendable {
        public let id: Int64
        public let name: String?
        public let description: String?

        public init(id: Int64, name: String? = nil, description: String? = nil) {
            self.id = id
            self.name = name
            self.description = description
        }
    }

    public struct MessagePushDTO: Encodable, Sendable {
        public let id: Int64?
        public let clientRequestId: String?
        public let senderId: Int64?
        public let receiverId: Int64?
        public let flashNoteId: Int64?
        public let content: String?
        public let role: String?
        public let readStatus: Bool?
        public let mediaType: String?
        public let mediaUrl: String?
        public let mediaDuration: Int64?
        public let thumbnailUrl: String?
        public let fileName: String?
        public let fileSize: Int64?
        public let createdAt: String?

        public init(
            id: Int64? = nil,
            clientRequestId: String? = nil,
            senderId: Int64? = nil,
            receiverId: Int64? = nil,
            flashNoteId: Int64? = nil,
            content: String? = nil,
            role: String? = nil,
            readStatus: Bool? = nil,
            mediaType: String? = nil,
            mediaUrl: String? = nil,
            mediaDuration: Int64? = nil,
            thumbnailUrl: String? = nil,
            fileName: String? = nil,
            fileSize: Int64? = nil,
            createdAt: String? = nil
        ) {
            self.id = id
            self.clientRequestId = clientRequestId
            self.senderId = senderId
            self.receiverId = receiverId
            self.flashNoteId = flashNoteId
            self.content = content
            self.role = role
            self.readStatus = readStatus
            self.mediaType = mediaType
            self.mediaUrl = mediaUrl
            self.mediaDuration = mediaDuration
            self.thumbnailUrl = thumbnailUrl
            self.fileName = fileName
            self.fileSize = fileSize
            self.createdAt = createdAt
        }
    }

    public struct FavoritePushDTO: Encodable, Sendable {
        public let messageId: Int64

        public init(messageId: Int64) {
            self.messageId = messageId
        }
    }
}

/// `/api/sync/push` 返回的 `accepted=true` + `processed={notes,collections,messages,favorites}` + `serverTime`。
public struct SyncPushResponse: Decodable, Sendable {
    public let accepted: Bool
    public let processed: SyncPushProcessed
    public let serverTime: String?

    public struct SyncPushProcessed: Decodable, Sendable, Equatable {
        public let notes: Int
        public let collections: Int
        public let messages: Int
        public let favorites: Int

        public init(notes: Int = 0, collections: Int = 0, messages: Int = 0, favorites: Int = 0) {
            self.notes = notes
            self.collections = collections
            self.messages = messages
            self.favorites = favorites
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.notes = try container.decodeIfPresent(Int.self, forKey: .notes) ?? 0
            self.collections = try container.decodeIfPresent(Int.self, forKey: .collections) ?? 0
            self.messages = try container.decodeIfPresent(Int.self, forKey: .messages) ?? 0
            self.favorites = try container.decodeIfPresent(Int.self, forKey: .favorites) ?? 0
        }

        private enum CodingKeys: String, CodingKey {
            case notes, collections, messages, favorites
        }
    }

    public init(accepted: Bool = false, processed: SyncPushProcessed = .init(), serverTime: String? = nil) {
        self.accepted = accepted
        self.processed = processed
        self.serverTime = serverTime
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accepted = try container.decodeIfPresent(Bool.self, forKey: .accepted) ?? false
        self.processed = try container.decodeIfPresent(SyncPushProcessed.self, forKey: .processed) ?? .init()
        self.serverTime = try container.decodeIfPresent(String.self, forKey: .serverTime)
    }

    private enum CodingKeys: String, CodingKey {
        case accepted, processed, serverTime
    }
}
