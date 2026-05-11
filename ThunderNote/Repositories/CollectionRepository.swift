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

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func list() async throws -> [Collection] {
        let endpoint = Endpoint<[Collection]>(
            method: .post,
            path: "/api/collections/list",
            body: nil,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        return try await apiClient.send(endpoint)
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
        return try await apiClient.send(endpoint)
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
        return try await apiClient.send(endpoint)
    }

    public func delete(id: Int64) async throws {
        let endpoint = Endpoint<EmptyResponse>(
            method: .delete,
            path: "/api/collections/\(id)",
            body: nil,
            requiresAuth: true
        )
        _ = try await apiClient.send(endpoint)
    }
}
