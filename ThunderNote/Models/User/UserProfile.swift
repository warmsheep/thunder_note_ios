import Foundation

/// 与服务端 `UserProfileResponse` + Android `UserProfile` 字段对齐的资料模型。
/// `createdAt / updatedAt` 走 LocalDateTime 字符串（与 Message 等其他实体一致）。
public struct UserProfile: Codable, Sendable, Equatable {
    public var id: Int64?
    public var userId: Int64?
    public var bio: String?
    public var preferencesJson: String?
    public var avatar: String?
    public var nickname: String?
    public var createdAt: String?
    public var updatedAt: String?

    public init(
        id: Int64? = nil,
        userId: Int64? = nil,
        bio: String? = nil,
        preferencesJson: String? = nil,
        avatar: String? = nil,
        nickname: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.bio = bio
        self.preferencesJson = preferencesJson
        self.avatar = avatar
        self.nickname = nickname
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// `PUT /api/users/avatar` 请求体。
public struct AvatarUpdateRequest: Encodable, Sendable {
    public let avatar: String

    public init(avatar: String) {
        self.avatar = avatar
    }
}
