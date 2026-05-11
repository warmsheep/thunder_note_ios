import Foundation

@MainActor
public final class FlashNoteListViewModel: ObservableObject {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    @Published public private(set) var notes: [FlashNote] = []
    @Published public private(set) var state: LoadState = .idle

    /// 从展示视图层弹出的 toast / 一次性事件。
    @Published public var transientMessage: String? = nil

    private let repository: FlashNoteRepository

    public init(repository: FlashNoteRepository) {
        self.repository = repository
    }

    public func load() async {
        if case .loading = state { return }
        state = .loading
        do {
            let raw = try await repository.list()
            notes = Self.sort(raw)
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

    /// 列表展示用过滤后的视图：默认隐藏 `hidden=true`，但保留收集箱。
    public var visibleNotes: [FlashNote] {
        notes.filter { note in
            note.isInbox || note.isHidden == false
        }
    }

    public func note(byId id: Int64) -> FlashNote? {
        notes.first { $0.id == id }
    }

    // MARK: - 操作

    public func togglePinned(_ note: FlashNote) async {
        if note.id == FlashNote.inboxId && note.isPinned {
            transientMessage = "收集箱不允许取消置顶"
            return
        }
        let nextValue = !note.isPinned
        do {
            try await repository.setPinned(id: note.id, value: nextValue)
            applyLocalUpdate(noteId: note.id) { local in
                local.pinned = nextValue
                if nextValue { local.hidden = false }
            }
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    public func toggleHidden(_ note: FlashNote) async {
        if note.isInbox {
            transientMessage = "收集箱不允许隐藏"
            return
        }
        let nextValue = !note.isHidden
        do {
            try await repository.setHidden(id: note.id, value: nextValue)
            applyLocalUpdate(noteId: note.id) { local in
                local.hidden = nextValue
                if nextValue { local.pinned = false }
            }
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    public func delete(_ note: FlashNote) async {
        if note.isInbox {
            transientMessage = "收集箱不可删除"
            return
        }
        do {
            try await repository.delete(id: note.id)
            notes.removeAll { $0.id == note.id }
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    /// 进入会话时若该闪记当前 hidden=true，自动 unhide（与 Android 行为对齐）。
    public func unhideIfNeeded(noteId: Int64) async {
        guard let note = note(byId: noteId), note.isHidden, !note.isInbox else { return }
        await toggleHidden(note)
    }

    public func upsertCreated(_ note: FlashNote) {
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = note
        } else {
            notes.append(note)
        }
        notes = Self.sort(notes)
    }

    /// 由编辑 / 操作完成后调用，覆盖本地缓存的对应项。
    public func upsertEdited(_ note: FlashNote) {
        upsertCreated(note)
    }

    public func clearTransientMessage() {
        transientMessage = nil
    }

    // MARK: - 私有

    private func applyLocalUpdate(noteId: Int64, _ mutator: (inout FlashNote) -> Void) {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return }
        var updated = notes[idx]
        mutator(&updated)
        notes[idx] = updated
        notes = Self.sort(notes)
    }

    /// 排序规则：
    /// 1. 收集箱（id == -1 或 inbox=true）始终置顶
    /// 2. 其他置顶项次之
    /// 3. 其余按 `updatedAt` 倒序
    static func sort(_ source: [FlashNote]) -> [FlashNote] {
        source.sorted { lhs, rhs in
            if lhs.isInbox && !rhs.isInbox { return true }
            if !lhs.isInbox && rhs.isInbox { return false }
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            let lhsKey = lhs.updatedAt ?? lhs.createdAt ?? ""
            let rhsKey = rhs.updatedAt ?? rhs.createdAt ?? ""
            if lhsKey != rhsKey { return lhsKey > rhsKey }
            return lhs.id > rhs.id
        }
    }
}
