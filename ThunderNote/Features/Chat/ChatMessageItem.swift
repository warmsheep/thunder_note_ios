import Foundation

/// UI 层统一的消息条目：覆盖远端已确认 + 本地待发送 + 失败三种状态。
public struct ChatMessageItem: Identifiable, Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case sent
        case pending
        case failed(reason: String)
    }

    public let clientRequestId: String?
    public let remoteId: Int64?
    /// D2-I7-05 Step 2C：关联的 pending_messages 表主键。
    public let pendingLocalId: Int64?
    public var status: Status
    public var message: Message

    public var id: String {
        if let remoteId, remoteId > 0 { return "remote:\(remoteId)" }
        if let clientRequestId { return "client:\(clientRequestId)" }
        return UUID().uuidString
    }

    public var isPending: Bool {
        if case .pending = status { return true }
        return false
    }

    public var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    /// 排序键：优先用远端 `createdAt`，pending 用 `localCreatedAt`。
    public var sortKey: String {
        message.createdAt ?? "9999-12-31T23:59:59"
    }
}
