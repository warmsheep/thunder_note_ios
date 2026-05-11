import Foundation

/// 统一向上抛出的 API 错误。错误码语义与后端约定（与 Android 错误码映射对齐）：
/// - `40000` 业务校验失败（参数错误）
/// - `40100` 未认证 / token 失效
/// - `40300` 无权限
/// - `40400` 资源不存在
/// - `50000` 服务端内部错误
public enum APIError: Error, Sendable, Equatable {
    /// 业务错误：包含后端返回的 `code` 与 `message`。
    case business(code: Int, message: String?)
    /// HTTP 状态码非 2xx 且无可解析的业务包装。
    case http(status: Int, message: String?)
    /// URL / 请求构造问题。
    case invalidRequest(reason: String)
    /// 解码失败。
    case decoding(message: String)
    /// 网络层错误（NSURLError 等）。
    case transport(message: String)
    /// 刷新 token 失败 / refreshToken 缺失，需要重新登录。
    case unauthenticated

    public var isUnauthorized: Bool {
        switch self {
        case .business(let code, _):
            return code == 40100 || code == 401
        case .http(let status, _):
            return status == 401
        case .unauthenticated:
            return true
        default:
            return false
        }
    }

    /// UI 层展示用的中文文案。
    public var displayMessage: String {
        switch self {
        case .business(_, let message):
            return message?.isEmpty == false ? message! : "服务器返回错误"
        case .http(let status, let message):
            return message?.isEmpty == false ? message! : "网络请求失败（HTTP \(status)）"
        case .invalidRequest(let reason):
            return "请求构造失败：\(reason)"
        case .decoding:
            return "服务器返回数据无法解析"
        case .transport(let message):
            return "网络异常：\(message)"
        case .unauthenticated:
            return "登录态已失效，请重新登录"
        }
    }
}
