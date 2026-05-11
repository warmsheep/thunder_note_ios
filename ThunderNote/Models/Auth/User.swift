import Foundation

/// 与后端 `User` / Android `User` 模型对齐的最小字段集合。
public struct User: Codable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let username: String
    public let email: String?
    public let nickname: String?
    public let avatar: String?
    public let bio: String?

    public init(
        id: Int64,
        username: String,
        email: String? = nil,
        nickname: String? = nil,
        avatar: String? = nil,
        bio: String? = nil
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.nickname = nickname
        self.avatar = avatar
        self.bio = bio
    }
}
