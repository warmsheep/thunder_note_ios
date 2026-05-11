import SwiftUI

struct FlashNoteListView: View {
    @StateObject var viewModel: FlashNoteListViewModel
    let editViewModelFactory: (FlashNoteEditViewModel.Mode) -> FlashNoteEditViewModel

    @State private var presentedEditMode: FlashNoteEditViewModel.Mode?
    @State private var pendingDeletion: FlashNote?
    @State private var showError: Bool = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("闪记")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbar }
                .refreshable { await viewModel.refresh() }
                .task { await viewModel.load() }
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
                .sheet(item: $presentedEditMode) { mode in
                    FlashNoteEditSheet(
                        viewModel: editViewModelFactory(mode),
                        onSaved: { note in
                            viewModel.upsertEdited(note)
                        }
                    )
                }
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
                FlashNoteRowView(note: note)
                    .contentShape(Rectangle())
                    .listRowSeparator(.visible)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !note.isInbox {
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

        if !note.isInbox {
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
                // 搜索入口占位：D2-I2-15 接入实际搜索页面
                viewModel.transientMessage = "搜索能力将在后续阶段接入"
            } label: {
                Image(systemName: "magnifyingglass")
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
