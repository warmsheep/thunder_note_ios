import Foundation

@MainActor
public final class CollectionsViewModel: ObservableObject {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    /// 一个分组：合集（含 id）或「未分类」（id=nil）。
    public struct Group: Identifiable, Equatable {
        public let collection: Collection?
        public var notes: [FlashNote]

        public var id: String {
            if let collection { return "collection:\(collection.id)" }
            return "uncategorized"
        }

        public var displayName: String {
            collection?.displayName ?? "未分类"
        }
    }

    @Published public private(set) var collections: [Collection] = []
    @Published public private(set) var groups: [Group] = []
    @Published public private(set) var state: LoadState = .idle
    @Published public var transientMessage: String? = nil

    private let collectionRepository: CollectionRepository
    private let flashNoteListViewModel: FlashNoteListViewModel

    public init(collectionRepository: CollectionRepository, flashNoteListViewModel: FlashNoteListViewModel) {
        self.collectionRepository = collectionRepository
        self.flashNoteListViewModel = flashNoteListViewModel
    }

    public func load() async {
        if case .loading = state { return }
        state = .loading
        do {
            // 闪记列表如果尚未加载，由 flash note tab 的 ViewModel 负责拉取；
            // 这里不重复触发，但可以等它就绪后再分组。
            if flashNoteListViewModel.notes.isEmpty {
                await flashNoteListViewModel.load()
            }
            let result = try await collectionRepository.list()
            collections = result.sorted { lhs, rhs in
                lhs.displayName < rhs.displayName
            }
            recomputeGroups()
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

    /// D2-I7：sync bootstrap / pull 返回 collections 快照时，直接更新本地合集与分组。
    public func applySyncSnapshot(collections: [Collection]) {
        self.collections = collections.sorted { lhs, rhs in
            lhs.displayName < rhs.displayName
        }
        recomputeGroups()
        if case .loading = state {
            state = .loaded
        }
    }

    public func recomputeGroups() {
        var byTag: [String: [FlashNote]] = [:]
        var uncategorized: [FlashNote] = []
        for note in flashNoteListViewModel.notes where note.isHidden == false || note.isInbox {
            let tag = note.tags?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if note.isInbox || tag.isEmpty {
                uncategorized.append(note)
            } else {
                byTag[tag, default: []].append(note)
            }
        }
        var result: [Group] = collections.map { collection in
            Group(collection: collection, notes: byTag[collection.displayName] ?? [])
        }
        if !uncategorized.isEmpty {
            result.append(Group(collection: nil, notes: uncategorized))
        }
        groups = result
    }

    // MARK: - CRUD

    public func createCollection(name: String) async -> Collection? {
        do {
            let created = try await collectionRepository.create(name: name)
            collections.append(created)
            collections.sort { $0.displayName < $1.displayName }
            recomputeGroups()
            return created
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch CollectionRepositoryError.nameEmpty {
            transientMessage = "请输入合集名称"
        } catch {
            transientMessage = error.localizedDescription
        }
        return nil
    }

    public func renameCollection(id: Int64, newName: String) async -> Collection? {
        do {
            let updated = try await collectionRepository.update(id: id, name: newName)
            if let idx = collections.firstIndex(where: { $0.id == id }) {
                collections[idx] = updated
            }
            collections.sort { $0.displayName < $1.displayName }
            recomputeGroups()
            return updated
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch CollectionRepositoryError.nameEmpty {
            transientMessage = "请输入合集名称"
        } catch {
            transientMessage = error.localizedDescription
        }
        return nil
    }

    public func delete(_ collection: Collection) async {
        do {
            try await collectionRepository.delete(id: collection.id)
            collections.removeAll { $0.id == collection.id }
            recomputeGroups()
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
