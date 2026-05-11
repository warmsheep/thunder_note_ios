import Foundation

/// 单次刷新去重：并发 N 个请求触发 401 时，只发起一次 `/api/auth/refresh`。
/// 失败时把当前会话置为登出态由调用方处理。
public actor RefreshActor {
    public typealias Performer = @Sendable () async throws -> LoginResponse

    private var inFlight: Task<LoginResponse, Error>?
    private let performer: Performer

    public init(performer: @escaping Performer) {
        self.performer = performer
    }

    /// 触发刷新；并发调用复用同一次实际网络请求。
    public func refresh() async throws -> LoginResponse {
        if let task = inFlight {
            return try await task.value
        }
        let performer = self.performer
        let task = Task<LoginResponse, Error> {
            try await performer()
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
