import Foundation

/// D2-I2-15 闪记列表搜索 ViewModel。
///
/// 与 Android `FlashNoteTabFragment.performSearch` + `FlashNoteRepositoryImpl
/// .searchNotes` 行为对齐：
/// - 输入变化 300ms 防抖；空查询直接清空结果，不发请求。
/// - 非空查询 trim 后调 `POST /api/flash-notes/search`，结果分两段
///   `noteNameMatched` / `messageContentMatched`。
/// - 任意一次搜索期间再次输入会取消上一个 in-flight 任务，避免竞态。
///
/// 视图层：`FlashNoteListView` 切到搜索面板时显式调 `onActivate()` 复位状态；
/// 关闭搜索时调 `onDeactivate()` 取消 in-flight 任务并清空。
@MainActor
public final class FlashNoteSearchViewModel: ObservableObject {
    @Published public var query: String = ""
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var noteNameMatched: [FlashNoteSearchResult] = []
    @Published public private(set) var messageContentMatched: [FlashNoteSearchResult] = []
    @Published public var transientMessage: String? = nil

    /// 当前 trim 后的最新查询；视图层可据此判断是否处于搜索模式。
    @Published public private(set) var activeQuery: String = ""

    private let repository: FlashNoteRepository
    private let debounce: Duration
    private var debounceTask: Task<Void, Never>? = nil
    private var searchTask: Task<Void, Never>? = nil

    public init(repository: FlashNoteRepository, debounce: Duration = .milliseconds(300)) {
        self.repository = repository
        self.debounce = debounce
    }

    /// 是否需要展示「无结果」空态：搜索激活 + 已加载结束 + 两段都为空。
    public var isEmptyResult: Bool {
        !activeQuery.isEmpty && !isLoading
            && noteNameMatched.isEmpty && messageContentMatched.isEmpty
    }

    public var hasAnyResult: Bool {
        !noteNameMatched.isEmpty || !messageContentMatched.isEmpty
    }

    /// 视图层在 query 输入变化时调用。空查询走「立即清空」分支（与 Android
    /// `performSearch(query="")` 等价），非空查询进 300ms 防抖。
    public func onQueryChanged(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        debounceTask?.cancel()
        if trimmed.isEmpty {
            cancelInflight()
            activeQuery = ""
            noteNameMatched = []
            messageContentMatched = []
            isLoading = false
            return
        }
        let delay = debounce
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            if Task.isCancelled { return }
            await self?.runSearch(trimmed)
        }
    }

    /// 立即触发搜索（如「搜索框 return 键提交」）。
    public func submitNow() async {
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelInflight()
            activeQuery = ""
            noteNameMatched = []
            messageContentMatched = []
            return
        }
        await runSearch(trimmed)
    }

    /// 视图层激活搜索面板时调用，确保从干净状态开始。
    public func onActivate() {
        // 不清 query：用户切换 tab 回来时希望保留输入。
    }

    /// 视图层关闭搜索面板时调用：取消 in-flight、清空状态。
    public func onDeactivate() {
        debounceTask?.cancel()
        cancelInflight()
        query = ""
        activeQuery = ""
        noteNameMatched = []
        messageContentMatched = []
        isLoading = false
    }

    public func clearTransientMessage() {
        transientMessage = nil
    }

    // MARK: - 私有

    private func runSearch(_ trimmed: String) async {
        cancelInflight()
        isLoading = true
        activeQuery = trimmed
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.repository.search(query: trimmed)
                if Task.isCancelled { return }
                await MainActor.run {
                    // 仅当 activeQuery 仍是这次发起的 trimmed 才落地，避免乱序覆盖。
                    guard self.activeQuery == trimmed else { return }
                    self.noteNameMatched = response.noteNameMatched
                    self.messageContentMatched = response.messageContentMatched
                    self.isLoading = false
                }
            } catch is CancellationError {
                // ignore
            } catch let api as APIError {
                if Task.isCancelled { return }
                await MainActor.run {
                    guard self.activeQuery == trimmed else { return }
                    self.transientMessage = api.displayMessage
                    self.isLoading = false
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    guard self.activeQuery == trimmed else { return }
                    self.transientMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
        searchTask = task
        await task.value
    }

    private func cancelInflight() {
        searchTask?.cancel()
        searchTask = nil
    }
}
