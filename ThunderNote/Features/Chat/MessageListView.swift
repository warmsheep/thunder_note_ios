import SwiftUI

/// 消息列表视图：负责按 `MessageTimeFormatter` 时间分组显示 separator，
/// 并把单条气泡委托给 `MessageBubble`。
struct MessageListView: View {
    let items: [ChatMessageItem]
    let key: ConversationKey
    let currentUserId: Int64?
    let isLoadingMore: Bool
    let hasMoreOlder: Bool
    let highlightedMessageId: Int64?
    let scrollTargetMessageId: Int64?
    let mediaUrlResolver: MediaUrlResolver?
    let isFavorited: (ChatMessageItem) -> Bool
    let onCopy: (ChatMessageItem) -> Void
    let onDelete: (ChatMessageItem) -> Void
    let onRetry: (ChatMessageItem) -> Void
    let onToggleFavorite: (ChatMessageItem) -> Void
    let onTapMediaAttachment: (ChatMessageItem) -> Void
    let onReachedTop: () -> Void
    let onScrollTargetConsumed: () -> Void

    @Binding var scrollToken: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    if hasMoreOlder {
                        loadMoreSpinner
                            .onAppear { onReachedTop() }
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                        let separator = separatorIfNeeded(for: item)
                        if let separator {
                            timeSeparator(text: separator)
                                .id("\(item.id)-sep")
                        }
                        MessageBubble(
                            item: item,
                            key: key,
                            currentUserId: currentUserId,
                            isFavorited: isFavorited(item),
                            isHighlighted: item.remoteId == highlightedMessageId && highlightedMessageId != nil,
                            mediaUrlResolver: mediaUrlResolver,
                            onCopy: { onCopy(item) },
                            onDelete: { onDelete(item) },
                            onRetry: { onRetry(item) },
                            onToggleFavorite: { onToggleFavorite(item) },
                            onTapMediaAttachment: { onTapMediaAttachment(item) }
                        )
                        .id(item.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("__chat_bottom__")
                }
                .padding(.vertical, DesignTokens.Spacing.small)
            }
            .onChange(of: items.last?.id) { _ in
                // 仅在没有 scrollTarget 时才自动滚到底，避免与 scrollToMessageId 冲突。
                if scrollTargetMessageId == nil {
                    proxy.scrollTo("__chat_bottom__", anchor: .bottom)
                }
            }
            .onChange(of: scrollToken) { _ in
                if scrollTargetMessageId == nil {
                    proxy.scrollTo("__chat_bottom__", anchor: .bottom)
                }
            }
            .onChange(of: scrollTargetMessageId) { newValue in
                guard let targetId = newValue else { return }
                let anchorId = "remote:\(targetId)"
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(anchorId, anchor: .center)
                }
                onScrollTargetConsumed()
            }
        }
        .accessibilityIdentifier("chatMessageList")
    }

    private var loadMoreSpinner: some View {
        HStack {
            Spacer()
            if isLoadingMore {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(DesignTokens.Color.brandPrimary)
            } else {
                Text("下拉加载更早消息")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Color.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }

    private func timeSeparator(text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityIdentifier("messageTimeSeparator")
    }

    private func separatorIfNeeded(for current: ChatMessageItem) -> String? {
        guard let date = MessageTimeFormatter.parse(current.message.createdAt) else { return nil }
        let previous: Date? = {
            guard let idx = items.firstIndex(where: { $0.id == current.id }), idx > 0 else { return nil }
            return MessageTimeFormatter.parse(items[idx - 1].message.createdAt)
        }()
        guard MessageTimeFormatter.shouldShowSeparator(previous: previous, current: date) else { return nil }
        return MessageTimeFormatter.separatorLabel(for: date)
    }
}
