import SwiftUI

/// 三模式公共聊天页骨架。
struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    let onAppearAutoUnhide: (() async -> Void)?

    @State private var scrollToken: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            content
            ChatInputBar(
                text: $viewModel.inputText,
                isSending: viewModel.isSending,
                onSend: {
                    Task { await viewModel.sendText() }
                }
            )
        }
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("chatView-\(viewModel.key.descriptor)")
        .task {
            await viewModel.onAppear()
            // 触发首次滚到底
            scrollToken = UUID()
            // D2-I2-08：进入会话时自动 unhide 该闪记
            if let onAppearAutoUnhide {
                await onAppearAutoUnhide()
            }
        }
        .onDisappear { viewModel.onDisappear() }
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

    @ViewBuilder
    private var content: some View {
        if viewModel.items.isEmpty {
            switch viewModel.loadState {
            case .idle, .loading:
                loadingView
            case .error(let message):
                errorView(message: message)
            case .loaded:
                emptyView
            }
        } else {
            MessageListView(
                items: viewModel.items,
                key: viewModel.key,
                currentUserId: viewModel.currentUserId,
                isLoadingMore: viewModel.isLoadingMore,
                hasMoreOlder: viewModel.hasMoreOlder,
                onCopy: { item in
                    UIPasteboard.general.string = item.message.content ?? ""
                },
                onDelete: { item in
                    Task { await viewModel.delete(item) }
                },
                onRetry: { item in
                    Task { await viewModel.retry(item) }
                },
                onReachedTop: {
                    Task { await viewModel.loadMoreOlder() }
                },
                scrollToken: $scrollToken
            )
        }
    }

    private var emptyView: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.Color.textSecondary)
            Text("还没有消息")
                .font(DesignTokens.Typography.title)
            Text("从下方输入第一条消息")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
