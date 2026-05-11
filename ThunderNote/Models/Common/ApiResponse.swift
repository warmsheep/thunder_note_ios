import Foundation

/// 与后端 `{ code, message, data, timestamp }` 包装一致。
/// `code == 0 || 200 || 201` 视为业务成功（与 Android `ApiResponse.isSuccess` 对齐）。
public struct ApiResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public let code: Int
    public let message: String?
    public let data: T?
    public let timestamp: Int64?

    public var isSuccess: Bool {
        code == 0 || code == 200 || code == 201
    }
}

/// 用于 `data == null` 的接口（logout / register / changePassword 等）。
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}
