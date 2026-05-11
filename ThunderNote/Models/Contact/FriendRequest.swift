import Foundation

/// 我收到的好友请求条目（与 Android `FriendRequest.java` 字段对齐）。
public struct FriendRequest: Codable, Sendable, Equatable, Identifiable {
    public var requestId: Int64
    public var userId: Int64?
    public var username: String?
    public var nickname: String?
    public var avatar: String?

    public var id: Int64 { requestId }

    public var displayName: String {
        if let nickname, !nickname.isEmpty { return nickname }
        if let username, !username.isEmpty { return username }
        return "未命名"
    }

    public init(
        requestId: Int64,
        userId: Int64? = nil,
        username: String? = nil,
        nickname: String? = nil,
        avatar: String? = nil
    ) {
        self.requestId = requestId
        self.userId = userId
        self.username = username
        self.nickname = nickname
        self.avatar = avatar
    }
}
