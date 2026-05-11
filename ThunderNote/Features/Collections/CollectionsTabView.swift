import SwiftUI

struct CollectionsTabView: View {
    @EnvironmentObject private var viewModel: CollectionsViewModel
    @EnvironmentObject private var flashNoteListViewModel: FlashNoteListViewModel
    @EnvironmentObject private var dependencies: AppDependencies

    @State private var path: [ChatRoute] = []
    @State private var presentedEdit: CollectionEditSheet.Mode?
    @State private var pendingDeletion: Collection?

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("合集")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            presentedEdit = .create
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityIdentifier("collectionAddButton")
                    }
                }
                .refreshable { await viewModel.refresh() }
                .task { await viewModel.load() }
                .onReceive(flashNoteListViewModel.$notes) { _ in
                    viewModel.recomputeGroups()
                }
                .navigationDestination(for: ChatRoute.self) { route in
                    ChatView(
                        viewModel: dependencies.makeChatViewModel(
                            key: route.key,
                            title: route.title,
                            targetMessageId: route.targetMessageId
                        ),
                        onAppearAutoUnhide: route.flashNoteId.map { id in
                            { await flashNoteListViewModel.unhideIfNeeded(noteId: id) }
                        }
                    )
                }
                .sheet(item: $presentedEdit) { mode in
                    CollectionEditSheet(mode: mode) { name in
                        switch mode {
                        case .create:
                            _ = await viewModel.createCollection(name: name)
                        case .rename(let collection):
                            _ = await viewModel.renameCollection(id: collection.id, newName: name)
                        }
                    }
                }
                .alert(
                    "确认删除该合集？",
                    isPresented: Binding(
                        get: { pendingDeletion != nil },
                        set: { if !$0 { pendingDeletion = nil } }
                    ),
                    presenting: pendingDeletion
                ) { collection in
                    Button("删除", role: .destructive) {
                        Task {
                            await viewModel.delete(collection)
                            pendingDeletion = nil
                        }
                    }
                    Button("取消", role: .cancel) { pendingDeletion = nil }
                } message: { collection in
                    Text("「\(collection.displayName)」将被删除，合集内的闪记会变为「未分类」。")
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
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.groups.isEmpty {
            switch viewModel.state {
            case .idle, .loading:
                loadingView
            case .error(let message):
                errorView(message: message)
            case .loaded:
                emptyView
            }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(viewModel.groups) { group in
                Section {
                    if group.notes.isEmpty {
                        Text("暂无闪记")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Color.textSecondary)
                    } else {
                        ForEach(group.notes) { note in
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
                        }
                    }
                } header: {
                    HStack {
                        Text(group.displayName)
                            .font(DesignTokens.Typography.bodyEmphasized)
                        Spacer()
                        if let collection = group.collection {
                            Menu {
                                Button("重命名") { presentedEdit = .rename(collection) }
                                Button("删除", role: .destructive) { pendingDeletion = collection }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(DesignTokens.Color.brandPrimary)
                            }
                            .accessibilityIdentifier("collectionMenu-\(collection.id)")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("collectionsList")
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView().tint(DesignTokens.Color.brandPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.Color.danger)
            Text(message)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.textSecondary)
            Button("重试") { Task { await viewModel.refresh() } }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.Color.brandPrimary)
        }
        .padding(DesignTokens.Spacing.large)
    }

    private var emptyView: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(DesignTokens.Color.textSecondary)
            Text("还没有合集")
                .font(DesignTokens.Typography.title)
            Text("点击右上角加号创建合集")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
