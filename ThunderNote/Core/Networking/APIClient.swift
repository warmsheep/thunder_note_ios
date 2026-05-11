import Foundation

/// 网络请求执行器。负责：
/// - 拼接 BaseURL（来自 `ServerConfigStore`）
/// - 注入 `Authorization` / `Accept-Language` / `User-Agent` 请求头
/// - 解析 `ApiResponse<T>` 包装并把业务错误码映射为 `APIError`
/// - 401 / 业务码 40100 时通过 `RefreshActor` 单次刷新并重试一次
public final class APIClient: @unchecked Sendable {
    /// 提供给 `RefreshActor` 与 `APIClient` 共享的 token 读写抽象。
    public protocol TokenAccessor: Sendable {
        func currentAccessToken() async -> String?
        func currentRefreshToken() async -> String?
        func saveSession(_ response: LoginResponse) async
        func clearSession() async
    }

    private let session: URLSession
    private let serverConfigStore: ServerConfigStoreProviding
    private let tokenAccessor: TokenAccessor
    private let decoder: JSONDecoder
    private let userAgent: String
    private let acceptLanguage: String
    private let refreshActor: RefreshActor

    public init(
        session: URLSession,
        serverConfigStore: ServerConfigStoreProviding,
        tokenAccessor: TokenAccessor,
        decoder: JSONDecoder = .tnDefault,
        userAgent: String = APIClient.defaultUserAgent(),
        acceptLanguage: String = APIClient.defaultAcceptLanguage()
    ) {
        self.session = session
        self.serverConfigStore = serverConfigStore
        self.tokenAccessor = tokenAccessor
        self.decoder = decoder
        self.userAgent = userAgent
        self.acceptLanguage = acceptLanguage
        // 把刷新所需的最小依赖以值语义捕获，避免 self 循环引用与 Sendable 冲突。
        let refreshDependencies = RefreshDependencies(
            session: session,
            serverConfigStore: serverConfigStore,
            tokenAccessor: tokenAccessor,
            decoder: decoder,
            userAgent: userAgent,
            acceptLanguage: acceptLanguage
        )
        self.refreshActor = RefreshActor {
            try await refreshDependencies.performRefresh()
        }
    }

    /// 发送请求并解码 `data` 字段。
    /// - 401 / 业务码 40100：尝试刷新 token 一次后重试；仍失败抛 `.unauthenticated`。
    public func send<T: Decodable & Sendable>(_ endpoint: Endpoint<T>) async throws -> T {
        try await sendInternal(endpoint, allowRetry: true)
    }

    private func sendInternal<T: Decodable & Sendable>(
        _ endpoint: Endpoint<T>,
        allowRetry: Bool
    ) async throws -> T {
        let request = try await buildRequest(for: endpoint)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.transport(message: error.localizedDescription)
        } catch {
            throw APIError.transport(message: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(message: "无效的响应类型")
        }

        // 优先尝试解码 ApiResponse 包装；失败则按 HTTP 状态码兜底。
        if let api = try? decoder.decode(ApiResponse<T>.self, from: data) {
            if api.isSuccess {
                guard let value = api.data else {
                    if let empty = EmptyResponse() as? T {
                        return empty
                    }
                    throw APIError.decoding(message: "缺少 data 字段")
                }
                return value
            }
            // 业务错误：401 / 40100 走刷新链路
            if (api.code == 40100 || api.code == 401) && allowRetry && endpoint.requiresAuth {
                try await performRefresh()
                return try await sendInternal(endpoint, allowRetry: false)
            }
            throw APIError.business(code: api.code, message: api.message)
        }

        // 没有业务包装：HTTP 401 也尝试一次刷新
        if http.statusCode == 401 && allowRetry && endpoint.requiresAuth {
            try await performRefresh()
            return try await sendInternal(endpoint, allowRetry: false)
        }

        if (200..<300).contains(http.statusCode) {
            // 走到这里说明响应不是 ApiResponse 包装但 HTTP 成功；尝试直接解码 T
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(message: String(describing: error))
            }
        }
        throw APIError.http(status: http.statusCode, message: String(data: data, encoding: .utf8))
    }

    private func buildRequest<T>(for endpoint: Endpoint<T>) async throws -> URLRequest {
        let baseURL = serverConfigStore.currentBaseURL
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidRequest(reason: "BaseURL 非法：\(baseURL.absoluteString)")
        }
        let trimmedBasePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let normalizedPath = endpoint.path.hasPrefix("/") ? endpoint.path : "/" + endpoint.path
        components.path = trimmedBasePath + normalizedPath
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query
        }
        guard let url = components.url else {
            throw APIError.invalidRequest(reason: "无法拼接 URL：\(endpoint.path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        for (key, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if endpoint.requiresAuth, let token = await tokenAccessor.currentAccessToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// 触发一次刷新；失败时清空会话并抛 `.unauthenticated`。
    private func performRefresh() async throws {
        do {
            let response = try await refreshActor.refresh()
            await tokenAccessor.saveSession(response)
        } catch let apiError as APIError {
            await tokenAccessor.clearSession()
            throw apiError.isUnauthorized ? APIError.unauthenticated : apiError
        } catch {
            await tokenAccessor.clearSession()
            throw APIError.unauthenticated
        }
    }

    public static func defaultUserAgent() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        return "ThunderNote/\(version)(\(build)) iOS/\(osVersion)"
    }

    public static func defaultAcceptLanguage() -> String {
        Locale.preferredLanguages.first ?? "zh-Hans"
    }
}

/// 把刷新 token 所需的最小依赖打包成 Sendable 值类型，让 `RefreshActor` 的 performer 闭包不需要捕获
/// `APIClient`，避免循环引用并满足 Swift 严格并发的 `@Sendable` 要求。
private struct RefreshDependencies: @unchecked Sendable {
    let session: URLSession
    let serverConfigStore: ServerConfigStoreProviding
    let tokenAccessor: APIClient.TokenAccessor
    let decoder: JSONDecoder
    let userAgent: String
    let acceptLanguage: String

    func performRefresh() async throws -> LoginResponse {
        guard let refreshToken = await tokenAccessor.currentRefreshToken(), !refreshToken.isEmpty else {
            throw APIError.unauthenticated
        }
        let body = try JSONEncoder.tnDefault.encode(RefreshTokenRequest(refreshToken: refreshToken))
        let baseURL = serverConfigStore.currentBaseURL
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidRequest(reason: "BaseURL 非法：\(baseURL.absoluteString)")
        }
        let trimmed = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = trimmed + "/api/auth/refresh"
        guard let url = components.url else {
            throw APIError.invalidRequest(reason: "无法拼接 refresh URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(message: "无效的响应类型")
        }
        if let api = try? decoder.decode(ApiResponse<LoginResponse>.self, from: data) {
            if api.isSuccess, let value = api.data {
                return value
            }
            throw APIError.business(code: api.code, message: api.message)
        }
        throw APIError.http(status: http.statusCode, message: String(data: data, encoding: .utf8))
    }
}
