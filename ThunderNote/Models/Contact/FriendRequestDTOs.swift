import Foundation

public struct FriendRequestCreateRequest: Encodable, Sendable {
    public let targetUserId: Int64
    public init(targetUserId: Int64) { self.targetUserId = targetUserId }
}

public struct FriendRequestActionRequest: Encodable, Sendable {
    public let requestId: Int64
    public init(requestId: Int64) { self.requestId = requestId }
}

/// `GET /api/users/contacts/requests/count` 返回 data=Long。
/// 直接用 `Int64` 解码会带来包装问题，做个透明 wrapper。
public struct FriendRequestUnreadCount: Decodable, Sendable {
    public let value: Int64

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(Int64.self)
    }
}
