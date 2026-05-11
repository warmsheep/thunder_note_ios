import Foundation

/// 联系人列表条目（与 Android `ContactUser.java` 字段对齐）。
/// 后端约定 `relationStatus` 在该列表里只会是 `FRIEND` / `PENDING_SENT` / `PENDING_RECEIVED`。
public struct ContactUser: Codable, Sendable, Equatable, Identifiable {
    public var userId: Int64
    public var username: String?
    public var nickname: String?
    public var avatar: String?
    public var relationStatusRaw: String?
    public var latestMessage: String?

    public var id: Int64 { userId }

    public var relationStatus: RelationStatus {
        RelationStatus(raw: relationStatusRaw)
    }

    public var displayName: String {
        if let nickname, !nickname.isEmpty { return nickname }
        if let username, !username.isEmpty { return username }
        return "未命名"
    }

    public init(
        userId: Int64,
        username: String? = nil,
        nickname: String? = nil,
        avatar: String? = nil,
        relationStatus: RelationStatus? = nil,
        latestMessage: String? = nil
    ) {
        self.userId = userId
        self.username = username
        self.nickname = nickname
        self.avatar = avatar
        self.relationStatusRaw = relationStatus?.rawValue
        self.latestMessage = latestMessage
    }

    private enum CodingKeys: String, CodingKey {
        case userId, username, nickname, avatar
        case relationStatusRaw = "relationStatus"
        case latestMessage
    }
}
