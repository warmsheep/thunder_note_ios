import Foundation

/// 登录 / 刷新 token 接口的响应体。
/// 字段名与后端 JSON 严格保持一致：
/// `accessToken / refreshToken / tokenType / expiresIn / user`
public struct LoginResponse: Decodable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let tokenType: String?
    /// 后端单位为毫秒（与 Android `LoginResponse.expiresIn` 对齐）。
    public let expiresIn: Int64
    public let user: User
}
