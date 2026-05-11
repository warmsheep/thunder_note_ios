import SwiftUI

struct FavoritesTabView: View {
    @EnvironmentObject private var viewModel: FavoritesViewModel
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var flashNoteListViewModel: FlashNoteListViewModel

    @State private var path: [ChatRoute] = []
    @State private var pendingRemoval: FavoriteItem?
    @State private var toast: String? = nil

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("收藏")
                .navigationBarTitleDisplayMode(.large)
                .refreshable { await viewModel.refresh() }
                .task { await viewModel.load() }
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
                .alert(
                    "确认取消收藏？",
                    isPresented: Binding(
                        get: { pendingRemoval != nil },
                        set: { if !$0 { pendingRemoval = nil } }
                    ),
                    presenting: pendingRemoval
                ) { item in
                    Button("取消收藏", role: .destructive) {
                        Task {
                            await viewModel.remove(item)
                            pendingRemoval = nil
                        }
                    }
                    Button("取消", role: .cancel) { pendingRemoval = nil }
                } message: { _ in
                    Text("该收藏将从你的收藏列表中移除。")
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
                    "提示",
                    isPresented: Binding(
                        get: { toast != nil },
                        set: { if !$0 { toast = nil } }
                    )
                ) {
                    Button("好") { toast = nil }
                } message: {
                    Text(toast ?? "")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.items.isEmpty {
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
        List(viewModel.items) { item in
            Button {
                handleTap(item)
            } label: {
                FavoriteRowView(item: item)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    pendingRemoval = item
                } label: {
                    Label("取消收藏", systemImage: "star.slash")
                }
                .accessibilityIdentifier("favoriteSwipeRemove-\(item.id)")
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("favoriteList")
    }

    private func handleTap(_ item: FavoriteItem) {
        guard let flashNoteId = item.flashNoteId else {
            // 「该收藏未关联闪记」与 Android 等价提示
            toast = "该收藏未关联闪记"
            return
        }
        path.append(ChatRoute(
            key: .flashNote(flashNoteId),
            title: item.displayTitle,
            flashNoteId: flashNoteId == FlashNote.inboxId ? nil : flashNoteId,
            targetMessageId: item.messageId
        ))
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
            Image(systemName: "star")
                .font(.system(size: 48))
                .foregroundStyle(DesignTokens.Color.textSecondary)
            Text("还没有收藏")
                .font(DesignTokens.Typography.title)
            Text("在聊天页长按消息可加入收藏")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
