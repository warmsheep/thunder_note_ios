import Foundation

/// 搜索结果条目。`relationStatus` 这里可能取 `NONE`（与列表 / 请求接口区分）。
public struct ContactSearchUser: Codable, Sendable, Equatable, Identifiable {
    public var userId: Int64
    public var username: String?
    public var nickname: String?
    public var avatar: String?
    public var relationStatusRaw: String?

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
        relationStatus: RelationStatus? = nil
    ) {
        self.userId = userId
        self.username = username
        self.nickname = nickname
        self.avatar = avatar
        self.relationStatusRaw = relationStatus?.rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case userId, username, nickname, avatar
        case relationStatusRaw = "relationStatus"
    }
}
