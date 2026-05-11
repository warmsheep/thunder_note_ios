import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct FlashNoteListView: View {
    @StateObject var viewModel: FlashNoteListViewModel
    @StateObject var searchViewModel: FlashNoteSearchViewModel
    let editViewModelFactory: (FlashNoteEditViewModel.Mode) -> FlashNoteEditViewModel
    let chatViewModelFactory: (ConversationKey, String, Int64?) -> ChatViewModel

    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var shareInboxConsumer: ShareInboxConsumer
    @EnvironmentObject private var contactsViewModel: ContactsViewModel

    @State private var presentedEditMode: FlashNoteEditViewModel.Mode?
    @State private var pendingDeletion: FlashNote?
    @State private var showError: Bool = false
    @State private var path: [ChatRoute] = []
    @State private var shareInboxEntry: ShareInboxEntry?
    /// D2-I2-11 是否弹出「清空收集箱」二次确认。
    @State private var presentClearInboxConfirm: Bool = false

    // MARK: - D2-I2-13 / D2-I2-14 快速捕获状态
    @State private var presentQuickCaptureMenu: Bool = false
    @State private var presentQuickCaptureText: Bool = false
    @State private var presentQuickCaptureImagePicker: Bool = false
    @State private var presentQuickCaptureVideoPicker: Bool = false
    @State private var presentQuickCaptureFilePicker: Bool = false
    @State private var presentQuickCaptureCamera: Bool = false
    @State private var presentQuickCaptureCard: Bool = false
    @StateObject private var quickCaptureImagePickerHelper = PhotosPickerHelper()
    @StateObject private var quickCaptureVideoPickerHelper = PhotosPickerHelper()

    // MARK: - D2-I2-15 搜索状态
    @State private var isSearchActive: Bool = false
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    ShareInboxBannerView(
                        pendingCount: shareInboxConsumer.pendingEntries.count,
                        onTap: {
                            shareInboxEntry = shareInboxConsumer.pendingEntries.first
                        }
                    )
                    if isSearchActive {
                        searchBar
                    }
                    if isSearchActive {
                        FlashNoteSearchPaneView(
                            viewModel: searchViewModel,
                            onPickResult: { note, messageId in
                                handleSearchPick(note: note, messageId: messageId)
                            }
                        )
                    } else {
                        content
                    }
                }
                // D2-I2-13 右下角快速捕获 FAB；点击弹出 6 入口菜单。
                QuickCaptureFAB(onTap: { presentQuickCaptureMenu = true })
                    .padding(.trailing, DesignTokens.Spacing.large)
                    .padding(.bottom, DesignTokens.Spacing.large)
            }
                .navigationTitle("闪记")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbar }
                .refreshable { await viewModel.refresh() }
                .task { await viewModel.load() }
                .navigationDestination(for: ChatRoute.self) { route in
                    ChatView(
                        viewModel: chatViewModelFactory(route.key, route.title, route.targetMessageId),
                        onAppearAutoUnhide: route.flashNoteId.map { id in
                            { await viewModel.unhideIfNeeded(noteId: id) }
                        }
                    )
                }
                .alert(
                    "确认删除该闪记？",
                    isPresented: Binding(
                        get: { pendingDeletion != nil },
                        set: { if !$0 { pendingDeletion = nil } }
                    ),
                    presenting: pendingDeletion
                ) { note in
                    Button("删除", role: .destructive) {
                        Task {
                            await viewModel.delete(note)
                            pendingDeletion = nil
                        }
                    }
                    Button("取消", role: .cancel) { pendingDeletion = nil }
                } message: { note in
                    Text("「\(note.displayTitle)」将被删除，删除后无法恢复。")
                }
                .alert(
                    "操作失败",
                    isPresented: Binding(
                        get: { viewModel.transientMessage != nil },
                        set: { if !$0 { viewModel.clearTransientMessage() } }
                    )
                ) {
                    Button("好") { viewModel.clearTransientMessage() }
                } message: {
                    Text(viewModel.transientMessage ?? "")
                }
                .alert(
                    "清空收集箱",
                    isPresented: $presentClearInboxConfirm
                ) {
                    Button("清空", role: .destructive) {
                        Task { await viewModel.clearInbox() }
                    }
                    .accessibilityIdentifier("flashNoteClearInboxConfirm")
                    Button("取消", role: .cancel) { }
                } message: {
                    Text("确定要清空收集箱所有消息吗？删除后不可恢复。")
                }
                .sheet(item: $presentedEditMode) { mode in
                    FlashNoteEditSheet(
                        viewModel: editViewModelFactory(mode),
                        onSaved: { note in
                            viewModel.upsertEdited(note)
                        }
                    )
                }
                .sheet(item: $shareInboxEntry) { entry in
                    ShareTargetPickerSheet(
                        entry: entry,
                        flashNotes: viewModel.visibleNotes,
                        contacts: contactsViewModel.friendContacts,
                        onSubmitText: { key in
                            await dependencies.submitShareEntryText(entry, key: key)
                        },
                        onDismiss: {
                            shareInboxConsumer.markConsumed(entry)
                        }
                    )
                }
                .modifier(QuickCaptureModifier(
                    presentMenu: $presentQuickCaptureMenu,
                    presentText: $presentQuickCaptureText,
                    presentImagePicker: $presentQuickCaptureImagePicker,
                    presentVideoPicker: $presentQuickCaptureVideoPicker,
                    presentFilePicker: $presentQuickCaptureFilePicker,
                    presentCamera: $presentQuickCaptureCamera,
                    presentCard: $presentQuickCaptureCard,
                    imagePickerHelper: quickCaptureImagePickerHelper,
                    videoPickerHelper: quickCaptureVideoPickerHelper,
                    dependencies: dependencies,
                    flashNoteListViewModel: viewModel
                ))
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.notes.isEmpty {
            switch viewModel.state {
            case .idle, .loading:
                loadingView
            case .error(let message):
                errorView(message: message)
            case .loaded:
                list
            }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(viewModel.visibleNotes) { note in
                Button {
                    path.append(ChatRoute(
                        key: .flashNote(note.id),
                        title: note.displayTitle,
                        flashNoteId: note.isInbox ? nil : note.id
                    ))
                } label: {
                    FlashNoteRowView(note: note)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.visible)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if note.isInbox {
                            // D2-I2-11 收集箱左滑：替代删除项，弹「清空收集箱」二次确认。
                            Button(role: .destructive) {
                                presentClearInboxConfirm = true
                            } label: {
                                Label("清空", systemImage: "tray")
                            }
                            .accessibilityIdentifier("flashNoteSwipeClearInbox")
                            .disabled(viewModel.isClearingInbox)
                        } else {
                            Button(role: .destructive) {
                                pendingDeletion = note
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .accessibilityIdentifier("flashNoteSwipeDelete-\(note.id)")
                        }
                    }
                    .contextMenu {
                        contextMenu(for: note)
                    }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("flashNoteList")
        .overlay {
            if viewModel.visibleNotes.isEmpty {
                emptyView
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for note: FlashNote) -> some View {
        if !note.isInbox {
            Button {
                presentedEditMode = .edit(note)
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .accessibilityIdentifier("flashNoteEditAction-\(note.id)")
        }

        Button {
            Task { await viewModel.togglePinned(note) }
        } label: {
            if note.isPinned {
                Label("取消置顶", systemImage: "pin.slash")
            } else {
                Label("置顶", systemImage: "pin")
            }
        }
        .accessibilityIdentifier("flashNotePinAction-\(note.id)")

        if note.isInbox {
            // D2-I2-11 收集箱长按菜单：唯一可破坏性入口为「清空收集箱」。
            Divider()
            Button(role: .destructive) {
                presentClearInboxConfirm = true
            } label: {
                Label("清空收集箱", systemImage: "tray")
            }
            .disabled(viewModel.isClearingInbox)
            .accessibilityIdentifier("flashNoteClearInboxAction")
        } else {
            Button {
                Task { await viewModel.toggleHidden(note) }
            } label: {
                if note.isHidden {
                    Label("取消隐藏", systemImage: "eye")
                } else {
                    Label("隐藏", systemImage: "eye.slash")
                }
            }
            .accessibilityIdentifier("flashNoteHideAction-\(note.id)")

            Divider()

            Button(role: .destructive) {
                pendingDeletion = note
            } label: {
                Label("删除", systemImage: "trash")
            }
            .accessibilityIdentifier("flashNoteDeleteAction-\(note.id)")
        }
    }

    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                toggleSearch()
            } label: {
                Image(systemName: isSearchActive ? "xmark" : "magnifyingglass")
            }
            .accessibilityIdentifier("flashNoteListSearchButton")

            Button {
                presentedEditMode = .create
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityIdentifier("flashNoteListAddButton")
        }
    }

    private var searchBar: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignTokens.Color.textSecondary)
            TextField("搜索闪记标题或消息", text: $searchViewModel.query)
                .textFieldStyle(.plain)
                .focused($searchFieldFocused)
                .submitLabel(.search)
                .onChange(of: searchViewModel.query) { newValue in
                    searchViewModel.onQueryChanged(newValue)
                }
                .onSubmit {
                    Task { await searchViewModel.submitNow() }
                }
                .accessibilityIdentifier("flashNoteSearchInput")
            if !searchViewModel.query.isEmpty {
                Button {
                    // 设空 query 由 onChange 触发 onQueryChanged("") 走清空分支。
                    searchViewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                }
                .accessibilityIdentifier("flashNoteSearchClearButton")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .padding(.vertical, 10)
        .background(DesignTokens.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .padding(.vertical, DesignTokens.Spacing.small)
    }

    private func toggleSearch() {
        if isSearchActive {
            searchViewModel.onDeactivate()
            searchFieldFocused = false
            isSearchActive = false
        } else {
            isSearchActive = true
            searchViewModel.onActivate()
            // 异步聚焦让搜索栏先 layout 出来，再触发 keyboard。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                searchFieldFocused = true
            }
        }
    }

    /// D2-I2-16 搜索结果点击 → 路由进入会话；非空 messageId 透传到
    /// `ChatRoute.targetMessageId`，由 `ChatViewModel`（D2-I3-05）做滚动 + 高亮。
    private func handleSearchPick(note: FlashNote, messageId: Int64?) {
        // 进入会话前先关闭搜索面板，避免 back 时仍处于搜索态。
        searchViewModel.onDeactivate()
        searchFieldFocused = false
        isSearchActive = false
        path.append(ChatRoute(
            key: .flashNote(note.id),
            title: note.displayTitle,
            flashNoteId: note.isInbox ? nil : note.id,
            targetMessageId: messageId
        ))
    }

    private var loadingView: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            ProgressView()
            Text("正在加载闪记…")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.Color.danger)
            Text("加载失败")
                .font(DesignTokens.Typography.title)
            Text(message)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignTokens.Spacing.large)
            Button("重试") { Task { await viewModel.refresh() } }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.Color.brandPrimary)
                .accessibilityIdentifier("flashNoteListRetryButton")
        }
        .padding(DesignTokens.Spacing.large)
    }

    private var emptyView: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48))
                .foregroundStyle(DesignTokens.Color.textSecondary)
            Text("还没有闪记")
                .font(DesignTokens.Typography.title)
            Text("点击右上角加号创建第一个闪记")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension FlashNoteEditViewModel.Mode: Identifiable {
    public var id: String {
        switch self {
        case .create: return "create"
        case .edit(let note): return "edit-\(note.id)"
        }
    }
}
