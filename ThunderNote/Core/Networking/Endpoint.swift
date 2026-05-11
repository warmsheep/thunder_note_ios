import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

/// API 请求描述。`T` 是 `data` 字段的目标类型（不带 `ApiResponse` 包装层）。
public struct Endpoint<T: Decodable & Sendable>: Sendable {
    public let method: HTTPMethod
    /// 相对路径，必须以 `/` 开头，例如 `/api/auth/login`。
    public let path: String
    public let query: [URLQueryItem]
    /// 已编码好的 JSON body；为 nil 表示无 body。
    public let body: Data?
    /// 是否需要在请求头注入 `Authorization: Bearer <accessToken>`。
    public let requiresAuth: Bool
    /// 额外请求头。
    public let headers: [String: String]

    public init(
        method: HTTPMethod,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        requiresAuth: Bool = true,
        headers: [String: String] = [:]
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.requiresAuth = requiresAuth
        self.headers = headers
    }
}

public extension Endpoint {
    /// 用 JSON 编码 body 的便捷构造器。
    static func json<Body: Encodable>(
        _ method: HTTPMethod,
        _ path: String,
        body: Body,
        requiresAuth: Bool = true,
        query: [URLQueryItem] = [],
        encoder: JSONEncoder = .tnDefault
    ) throws -> Endpoint<T> {
        let encoded = try encoder.encode(body)
        return Endpoint<T>(
            method: method,
            path: path,
            query: query,
            body: encoded,
            requiresAuth: requiresAuth,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
    }
}

public extension JSONEncoder {
    static var tnDefault: JSONEncoder {
        let encoder = JSONEncoder()
        return encoder
    }
}

public extension JSONDecoder {
    static var tnDefault: JSONDecoder {
        let decoder = JSONDecoder()
        return decoder
    }
}
