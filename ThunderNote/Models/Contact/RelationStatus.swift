import Foundation

/// 与后端 `relationStatus` 字段取值对齐：
/// - `FRIEND`：已是好友
/// - `PENDING_SENT`：我已发起、等待对方同意
/// - `PENDING_RECEIVED`：对方已发起、等待我同意
/// - `NONE`：无关系（仅出现在搜索结果里）
public enum RelationStatus: String, Codable, Sendable {
    case friend = "FRIEND"
    case pendingSent = "PENDING_SENT"
    case pendingReceived = "PENDING_RECEIVED"
    case none = "NONE"

    public init(raw: String?) {
        if let raw, let value = RelationStatus(rawValue: raw) {
            self = value
        } else {
            self = .none
        }
    }

    public var isFriend: Bool { self == .friend }
    public var isPending: Bool { self == .pendingSent || self == .pendingReceived }
}
