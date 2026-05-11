import Foundation

public protocol FlashNoteRepository: Sendable {
    /// 拉取当前用户的闪记列表（首位固定为收集箱）。
    func list() async throws -> [FlashNote]

    /// 创建闪记。当前后端契约：直接 POST `FlashNote` 实体形态。
    func create(title: String, icon: String?, tags: String?) async throws -> FlashNote

    /// 编辑闪记：标题 / 图标 / tags。`id == -1` 不允许编辑。
    func update(id: Int64, title: String, icon: String?, tags: String?) async throws -> FlashNote

    /// 置顶 / 取消置顶。`id == -1` 不允许取消置顶。
    func setPinned(id: Int64, value: Bool) async throws

    /// 隐藏 / 取消隐藏。`value=true` 时后端会自动取消置顶。`id == -1` 不允许隐藏。
    func setHidden(id: Int64, value: Bool) async throws

    /// 删除闪记。`id == -1` 是收集箱（虚拟节点），不允许删除。
    func delete(id: Int64) async throws
}

public enum FlashNoteRepositoryError: Error, Equatable {
    case inboxImmutable
    case titleEmpty
}

public final class FlashNoteRepositoryImpl: FlashNoteRepository, @unchecked Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func list() async throws -> [FlashNote] {
        let endpoint = Endpoint<[FlashNote]>(
            method: .post,
            path: "/api/flash-notes/list",
            body: nil,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        return try await apiClient.send(endpoint)
    }

    public func create(title: String, icon: String?, tags: String?) async throws -> FlashNote {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FlashNoteRepositoryError.titleEmpty }
        let payload = FlashNote(
            id: 0, // 服务端会忽略并分配新 id
            title: trimmed,
            icon: icon ?? FlashNoteIcons.defaultIcon,
            tags: tags?.isEmpty == true ? nil : tags
        )
        let body = try JSONEncoder.tnDefault.encode(payload)
        let endpoint = Endpoint<FlashNote>(
            method: .post,
            path: "/api/flash-notes",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        return try await apiClient.send(endpoint)
    }

    public func update(id: Int64, title: String, icon: String?, tags: String?) async throws -> FlashNote {
        guard id != FlashNote.inboxId else { throw FlashNoteRepositoryError.inboxImmutable }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FlashNoteRepositoryError.titleEmpty }
        let payload = FlashNote(
            id: id,
            title: trimmed,
            icon: icon,
            tags: tags?.isEmpty == true ? nil : tags
        )
        let body = try JSONEncoder.tnDefault.encode(payload)
        let endpoint = Endpoint<FlashNote>(
            method: .put,
            path: "/api/flash-notes/\(id)",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        return try await apiClient.send(endpoint)
    }

    public func setPinned(id: Int64, value: Bool) async throws {
        guard !(id == FlashNote.inboxId && value == false) else {
            throw FlashNoteRepositoryError.inboxImmutable
        }
        let endpoint = Endpoint<EmptyResponse>(
            method: .put,
            path: "/api/flash-notes/\(id)/pin",
            query: [URLQueryItem(name: "value", value: String(value))],
            body: nil,
            requiresAuth: true
        )
        _ = try await apiClient.send(endpoint)
    }

    public func setHidden(id: Int64, value: Bool) async throws {
        guard id != FlashNote.inboxId else { throw FlashNoteRepositoryError.inboxImmutable }
        let endpoint = Endpoint<EmptyResponse>(
            method: .put,
            path: "/api/flash-notes/\(id)/hide",
            query: [URLQueryItem(name: "value", value: String(value))],
            body: nil,
            requiresAuth: true
        )
        _ = try await apiClient.send(endpoint)
    }

    public func delete(id: Int64) async throws {
        guard id != FlashNote.inboxId else { throw FlashNoteRepositoryError.inboxImmutable }
        let endpoint = Endpoint<EmptyResponse>(
            method: .delete,
            path: "/api/flash-notes/\(id)",
            body: nil,
            requiresAuth: true
        )
        _ = try await apiClient.send(endpoint)
    }
}
