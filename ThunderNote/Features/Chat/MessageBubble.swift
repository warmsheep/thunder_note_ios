import SwiftUI

/// 单条消息气泡。
/// - 闪记会话（`flash:<id>`、`flash:-1`）默认全部右气泡（与 Android 闪记内对话一致）。
/// - 联系人会话（`peer:<userId>`）按 `senderId == currentUserId` 区分左右。
struct MessageBubble: View {
    let item: ChatMessageItem
    let key: ConversationKey
    let currentUserId: Int64?
    let isFavorited: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onRetry: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            if isOutgoing {
                Spacer(minLength: 48)
                bubble
            } else {
                bubble
                Spacer(minLength: 48)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .padding(.vertical, 4)
    }

    private var bubble: some View {
        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(bubbleForeground)
                .contextMenu {
                    Button {
                        onCopy()
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("messageActionCopy")

                    if let remoteId = item.remoteId, remoteId > 0 {
                        Button {
                            onToggleFavorite()
                        } label: {
                            if isFavorited {
                                Label("取消收藏", systemImage: "star.slash")
                            } else {
                                Label("收藏", systemImage: "star")
                            }
                        }
                        .accessibilityIdentifier("messageActionFavorite")
                    }

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .accessibilityIdentifier("messageActionDelete")
                }
            statusFooter
        }
        .accessibilityIdentifier("messageBubble-\(item.id)")
    }

    @ViewBuilder
    private var content: some View {
        switch item.message.resolvedMediaType {
        case .text:
            Text(MessageMarkdown.render(item.message.content ?? ""))
                .textSelection(.enabled)
        case .image, .video, .audio, .file, .composite:
            // 媒体类消息将在 D2-I3-08 ~ I3-19 实现。
            HStack(spacing: 8) {
                Image(systemName: mediaSymbol)
                Text(mediaPlaceholderLabel)
            }
        }
    }

    private var statusFooter: some View {
        HStack(spacing: 4) {
            if let date = MessageTimeFormatter.parse(item.message.createdAt) {
                Text(MessageTimeFormatter.bubbleTimeLabel(for: date))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Color.textSecondary)
            }
            if item.isPending {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Color.textSecondary)
                    .accessibilityIdentifier("messagePendingIcon")
            } else if item.isFailed {
                Button {
                    onRetry()
                } label: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("messageFailedRetryButton")
            }
        }
    }

    private var bubbleBackground: Color {
        if isOutgoing {
            return DesignTokens.Color.brandPrimary
        }
        return DesignTokens.Color.surface
    }

    private var bubbleForeground: Color {
        if isOutgoing {
            return .white
        }
        return DesignTokens.Color.textPrimary
    }

    /// 是否「我」发送的消息（决定气泡靠右 + 主色）。
    private var isOutgoing: Bool {
        switch key {
        case .flashNote:
            return true
        case .peer:
            guard let currentUserId, let senderId = item.message.senderId else { return false }
            return currentUserId == senderId
        }
    }

    private var mediaSymbol: String {
        switch item.message.resolvedMediaType {
        case .image: return "photo"
        case .video: return "play.rectangle"
        case .audio: return "waveform"
        case .file: return "doc"
        case .composite: return "rectangle.stack"
        default: return "doc.text"
        }
    }

    private var mediaPlaceholderLabel: String {
        switch item.message.resolvedMediaType {
        case .image: return "[图片]"
        case .video: return "[视频]"
        case .audio: return "[语音]"
        case .file: return "[文件]"
        case .composite: return "[卡片]"
        default: return ""
        }
    }
}
