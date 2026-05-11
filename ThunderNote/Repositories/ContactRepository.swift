import Foundation

public protocol ContactRepository: Sendable {
    func listContacts() async throws -> [ContactUser]
    func listFriendRequests() async throws -> [FriendRequest]
    func friendRequestCount() async throws -> Int64
    func sendFriendRequest(targetUserId: Int64) async throws
    func acceptFriendRequest(requestId: Int64) async throws
    func rejectFriendRequest(requestId: Int64) async throws
    func cancelOutgoingRequest(requestId: Int64) async throws
    func removeContact(userId: Int64) async throws
    func search(keyword: String) async throws -> [ContactSearchUser]
}

public final class ContactRepositoryImpl: ContactRepository, @unchecked Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func listContacts() async throws -> [ContactUser] {
        let endpoint = Endpoint<[ContactUser]>(
            method: .get,
            path: "/api/users/contacts",
            requiresAuth: true
        )
        return try await apiClient.send(endpoint)
    }

    public func listFriendRequests() async throws -> [FriendRequest] {
        let endpoint = Endpoint<[FriendRequest]>(
            method: .get,
            path: "/api/users/contacts/requests",
            requiresAuth: true
        )
        return try await apiClient.send(endpoint)
    }

    public func friendRequestCount() async throws -> Int64 {
        let endpoint = Endpoint<FriendRequestUnreadCount>(
            method: .get,
            path: "/api/users/contacts/requests/count",
            requiresAuth: true
        )
        let value = try await apiClient.send(endpoint)
        return value.value
    }

    public func sendFriendRequest(targetUserId: Int64) async throws {
        let body = try JSONEncoder.tnDefault.encode(FriendRequestCreateRequest(targetUserId: targetUserId))
        let endpoint = Endpoint<EmptyResponse>(
            method: .post,
            path: "/api/users/contacts/request",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        _ = try await apiClient.send(endpoint)
    }

    public func acceptFriendRequest(requestId: Int64) async throws {
        let body = try JSONEncoder.tnDefault.encode(FriendRequestActionRequest(requestId: requestId))
        let endpoint = Endpoint<EmptyResponse>(
            method: .post,
            path: "/api/users/contacts/request/accept",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        _ = try await apiClient.send(endpoint)
    }

    public func rejectFriendRequest(requestId: Int64) async throws {
        let body = try JSONEncoder.tnDefault.encode(FriendRequestActionRequest(requestId: requestId))
        let endpoint = Endpoint<EmptyResponse>(
            method: .post,
            path: "/api/users/contacts/request/reject",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        _ = try await apiClient.send(endpoint)
    }

    public func cancelOutgoingRequest(requestId: Int64) async throws {
        let endpoint = Endpoint<EmptyResponse>(
            method: .delete,
            path: "/api/users/contacts/request/\(requestId)",
            requiresAuth: true
        )
        _ = try await apiClient.send(endpoint)
    }

    public func removeContact(userId: Int64) async throws {
        let endpoint = Endpoint<EmptyResponse>(
            method: .delete,
            path: "/api/users/contacts/\(userId)",
            requiresAuth: true
        )
        _ = try await apiClient.send(endpoint)
    }

    public func search(keyword: String) async throws -> [ContactSearchUser] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let endpoint = Endpoint<[ContactSearchUser]>(
            method: .get,
            path: "/api/users/contacts/search",
            query: [URLQueryItem(name: "keyword", value: trimmed)],
            requiresAuth: true
        )
        return try await apiClient.send(endpoint)
    }
}
