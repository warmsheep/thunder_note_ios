import SwiftUI

/// 消息列表视图：负责按 `MessageTimeFormatter` 时间分组显示 separator，
/// 并把单条气泡委托给 `MessageBubble`。`onAppearTopItem` 用于触发分页。
struct MessageListView: View {
    let items: [ChatMessageItem]
    let key: ConversationKey
    let currentUserId: Int64?
    let isLoadingMore: Bool
    let hasMoreOlder: Bool
    let onCopy: (ChatMessageItem) -> Void
    let onDelete: (ChatMessageItem) -> Void
    let onRetry: (ChatMessageItem) -> Void
    let onReachedTop: () -> Void

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
                            onCopy: { onCopy(item) },
                            onDelete: { onDelete(item) },
                            onRetry: { onRetry(item) }
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
                proxy.scrollTo("__chat_bottom__", anchor: .bottom)
            }
            .onChange(of: scrollToken) { _ in
                proxy.scrollTo("__chat_bottom__", anchor: .bottom)
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
