import Foundation

@MainActor
public final class FavoritesViewModel: ObservableObject {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    @Published public private(set) var items: [FavoriteItem] = []
    @Published public private(set) var state: LoadState = .idle
    @Published public var transientMessage: String? = nil

    private let repository: FavoriteRepository
    private let registry: FavoriteIdRegistry

    public init(repository: FavoriteRepository, registry: FavoriteIdRegistry) {
        self.repository = repository
        self.registry = registry
    }

    public func load() async {
        if case .loading = state { return }
        state = .loading
        do {
            let raw = try await repository.list()
            items = raw.sorted { lhs, rhs in
                (lhs.favoritedAt ?? "") > (rhs.favoritedAt ?? "")
            }
            // 同步本地 registry
            registry.replaceAll(items.compactMap { $0.messageId })
            state = .loaded
        } catch let api as APIError {
            state = .error(api.displayMessage)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    public func refresh() async {
        await load()
    }

    public func remove(_ favorite: FavoriteItem) async {
        guard let messageId = favorite.messageId else {
            transientMessage = "缺少消息 ID，无法取消收藏"
            return
        }
        do {
            try await repository.unfavorite(messageId: messageId)
            items.removeAll { $0.id == favorite.id }
            registry.remove(messageId)
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    public func clearTransientMessage() {
        transientMessage = nil
    }
}
