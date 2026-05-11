import Foundation

public protocol FavoriteRepository: Sendable {
    func list() async throws -> [FavoriteItem]
    /// 收藏一条消息；已存在收藏时返回服务端现有记录（幂等）。
    func favorite(messageId: Int64) async throws -> FavoriteItem
    func unfavorite(messageId: Int64) async throws
}

public final class FavoriteRepositoryImpl: FavoriteRepository, @unchecked Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func list() async throws -> [FavoriteItem] {
        let endpoint = Endpoint<[FavoriteItem]>(
            method: .post,
            path: "/api/favorites/list",
            body: nil,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        return try await apiClient.send(endpoint)
    }

    public func favorite(messageId: Int64) async throws -> FavoriteItem {
        let endpoint = Endpoint<FavoriteItem>(
            method: .post,
            path: "/api/favorites/\(messageId)",
            body: nil,
            requiresAuth: true
        )
        return try await apiClient.send(endpoint)
    }

    public func unfavorite(messageId: Int64) async throws {
        let endpoint = Endpoint<EmptyResponse>(
            method: .delete,
            path: "/api/favorites/\(messageId)",
            body: nil,
            requiresAuth: true
        )
        _ = try await apiClient.send(endpoint)
    }
}
