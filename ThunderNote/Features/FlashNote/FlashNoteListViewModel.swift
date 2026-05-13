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
    /// D2-I2-11 清空收集箱期间的 inflight 标记。UI 层据此 disable 入口避免重复点击。
    @Published public private(set) var isClearingInbox: Bool = false

    /// 从展示视图层弹出的 toast / 一次性事件。
    @Published public var transientMessage: String? = nil

    private let repository: FlashNoteRepository
    private let messageRepository: MessageRepository?

    public init(
        repository: FlashNoteRepository,
        messageRepository: MessageRepository? = nil
    ) {
        self.repository = repository
        self.messageRepository = messageRepository
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

    /// D2-I2-11 清空收集箱：
    /// - 调 `MessageRepository.clearInbox()`（`DELETE /api/messages/clear-inbox`）。
    /// - 成功后把列表里 inbox 行的 `latestMessage` 抹掉，避免界面继续展示旧预览。
    /// - 失败仅 toast 一次，不锁死 UI（`isClearingInbox` 在 finally 一定复位）。
    public func clearInbox() async {
        guard let messageRepository else {
            transientMessage = "消息仓库未初始化，无法清空收集箱"
            return
        }
        if isClearingInbox { return }
        isClearingInbox = true
        defer { isClearingInbox = false }
        do {
            try await messageRepository.clearInbox()
            applyLocalUpdate(noteId: FlashNote.inboxId) { local in
                local.latestMessage = nil
            }
            messageRepository.clearLocalConversation(key: .flashNote(FlashNote.inboxId))
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    /// D2-I2-12 收集箱预览本地更新：
    /// 快速捕获 / Share Extension 等入口往收集箱发送一条消息后，立刻把列表
    /// 收集箱行的 `latestMessage` 与 `updatedAt` 更新到本地，**不等远端 sync 回来**，
    /// 避免用户感知到「发了之后列表预览还停在旧值上」。
    /// - 与 Android `FlashNoteRepositoryImpl.updateInboxPreviewLocally` 行为对齐：
    ///   预览空白 / 全是空白字符 → 跳过；非空 → trim 后写入。
    public func updateInboxPreviewLocally(_ latestMessage: String?) {
        guard let raw = latestMessage else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = LocalDateTimeFormatter.shared.string(from: Date())
        applyLocalUpdate(noteId: FlashNote.inboxId) { local in
            local.latestMessage = trimmed
            local.updatedAt = now
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

    /// D2-I7：sync bootstrap / pull 直接返回 notes 快照时，立即替换当前列表状态。
    /// 不触发额外网络刷新，避免刚 sync 完又重复 list 一次。
    public func applySyncSnapshot(_ notes: [FlashNote]) {
        self.notes = Self.sort(notes)
        if case .loading = state {
            state = .loaded
        }
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

    /// 与后端 `LocalDateTime` 序列化格式一致的轻量 formatter，仅用于本地写 `updatedAt`。
    /// 后端使用 `yyyy-MM-dd'T'HH:mm:ss`（无时区，无小数秒），iOS 端写回时保持等价。
    enum LocalDateTimeFormatter {
        static let shared: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return f
        }()
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
