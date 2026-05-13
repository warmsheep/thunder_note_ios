import Foundation

public protocol CollectionRepository: Sendable {
    func list() async throws -> [Collection]
    func create(name: String) async throws -> Collection
    func update(id: Int64, name: String) async throws -> Collection
    func delete(id: Int64) async throws
}

public enum CollectionRepositoryError: Error, Equatable {
    case nameEmpty
}

public final class CollectionRepositoryImpl: CollectionRepository, @unchecked Sendable {
    private let apiClient: APIClient
    private let localDao: CollectionLocalDao?
    private let usernameProvider: @Sendable () -> String?

    public init(
        apiClient: APIClient,
        localDao: CollectionLocalDao? = nil,
        usernameProvider: @Sendable @escaping () -> String? = { nil }
    ) {
        self.apiClient = apiClient
        self.localDao = localDao
        self.usernameProvider = usernameProvider
    }

    public func list() async throws -> [Collection] {
        if let dao = localDao, let username = usernameProvider(), !username.isEmpty {
            if let local = try? dao.listAll(username: username), !local.isEmpty {
                return local
            }
        }
        let endpoint = Endpoint<[Collection]>(
            method: .post,
            path: "/api/collections/list",
            body: nil,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        let collections = try await apiClient.send(endpoint)
        if let dao = localDao, let username = usernameProvider(), !username.isEmpty, !collections.isEmpty {
            try? dao.replaceAll(collections, username: username)
        }
        return collections
    }

    public func create(name: String) async throws -> Collection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CollectionRepositoryError.nameEmpty }
        let payload = Collection(id: 0, name: trimmed)
        let body = try JSONEncoder.tnDefault.encode(payload)
        let endpoint = Endpoint<Collection>(
            method: .post,
            path: "/api/collections",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        let result = try await apiClient.send(endpoint)
        if let dao = localDao, let username = usernameProvider(), !username.isEmpty {
            try? dao.upsert(result, username: username)
        }
        return result
    }

    public func update(id: Int64, name: String) async throws -> Collection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CollectionRepositoryError.nameEmpty }
        let payload = Collection(id: id, name: trimmed)
        let body = try JSONEncoder.tnDefault.encode(payload)
        let endpoint = Endpoint<Collection>(
            method: .put,
            path: "/api/collections/\(id)",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        let result = try await apiClient.send(endpoint)
        if let dao = localDao, let username = usernameProvider(), !username.isEmpty {
            try? dao.upsert(result, username: username)
        }
        return result
    }

    public func delete(id: Int64) async throws {
        let endpoint = Endpoint<EmptyResponse>(
            method: .delete,
            path: "/api/collections/\(id)",
            body: nil,
            requiresAuth: true
        )
        _ = try await apiClient.send(endpoint)
        if let dao = localDao, let username = usernameProvider(), !username.isEmpty {
            try? dao.delete(username: username, id: id)
        }
    }
}
