import Foundation

public protocol FavoriteRepository: Sendable {
    func list() async throws -> [FavoriteItem]
    /// 收藏一条消息；已存在收藏时返回服务端现有记录（幂等）。
    func favorite(messageId: Int64) async throws -> FavoriteItem
    func unfavorite(messageId: Int64) async throws
}

public final class FavoriteRepositoryImpl: FavoriteRepository, @unchecked Sendable {
    private let apiClient: APIClient
    private let localDao: FavoriteLocalDao?
    private let usernameProvider: @Sendable () -> String?

    public init(
        apiClient: APIClient,
        localDao: FavoriteLocalDao? = nil,
        usernameProvider: @Sendable @escaping () -> String? = { nil }
    ) {
        self.apiClient = apiClient
        self.localDao = localDao
        self.usernameProvider = usernameProvider
    }

    public func list() async throws -> [FavoriteItem] {
        if let dao = localDao, let username = usernameProvider(), !username.isEmpty {
            if let local = try? dao.listAll(username: username), !local.isEmpty {
                return local
            }
        }
        let endpoint = Endpoint<[FavoriteItem]>(
            method: .post,
            path: "/api/favorites/list",
            body: nil,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        let favorites = try await apiClient.send(endpoint)
        if let dao = localDao, let username = usernameProvider(), !username.isEmpty, !favorites.isEmpty {
            try? dao.replaceAll(favorites, username: username)
        }
        return favorites
    }

    public func favorite(messageId: Int64) async throws -> FavoriteItem {
        let endpoint = Endpoint<FavoriteItem>(
            method: .post,
            path: "/api/favorites/\(messageId)",
            body: nil,
            requiresAuth: true
        )
        let result = try await apiClient.send(endpoint)
        if let dao = localDao, let username = usernameProvider(), !username.isEmpty {
            try? dao.upsert(result, username: username)
        }
        return result
    }

    public func unfavorite(messageId: Int64) async throws {
        let endpoint = Endpoint<EmptyResponse>(
            method: .delete,
            path: "/api/favorites/\(messageId)",
            body: nil,
            requiresAuth: true
        )
        _ = try await apiClient.send(endpoint)
        if let dao = localDao, let username = usernameProvider(), !username.isEmpty {
            try? dao.deleteByMessageId(username: username, messageId: messageId)
        }
    }
}
