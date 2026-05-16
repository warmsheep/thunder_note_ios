import SwiftUI

/// 单条消息气泡。
/// - 闪记会话（`flash:<id>`、`flash:-1`）默认全部右气泡（与 Android 闪记内对话一致）。
/// - 联系人会话（`peer:<userId>`）按 `senderId == currentUserId` 区分左右。
struct MessageBubble: View {
    let item: ChatMessageItem
    let key: ConversationKey
    let currentUserId: Int64?
    let isFavorited: Bool
    let isHighlighted: Bool
    let isMultiSelectMode: Bool
    let isSelected: Bool
    let mediaUrlResolver: MediaUrlResolver?
    let fileRepository: FileRepository?
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onRetry: () -> Void
    let onToggleFavorite: () -> Void
    let onTapMediaAttachment: () -> Void
    let onLongPressForMultiSelect: () -> Void
    let onToggleSelection: () -> Void
    let onDownloadMedia: () -> Void
    let onOpenExternally: () -> Void
    let onForward: () -> Void
    let onOpenCardDetail: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if isMultiSelectMode {
                selectionCheckbox
            }
            HStack(alignment: .bottom) {
                if isOutgoing {
                    Spacer(minLength: 48)
                    bubble
                } else {
                    bubble
                    Spacer(minLength: 48)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if isMultiSelectMode {
                onToggleSelection()
            }
        }
    }

    /// 多选模式下展示在左侧的勾选框。
    private var selectionCheckbox: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .foregroundStyle(isSelected ? DesignTokens.Color.brandPrimary : DesignTokens.Color.textSecondary)
            .accessibilityIdentifier("messageSelectCheckbox-\(item.id)")
    }

    private var bubble: some View {
        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(bubbleForeground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isHighlighted ? Color.yellow : Color.clear,
                            lineWidth: 3
                        )
                        .animation(.easeInOut(duration: 0.4), value: isHighlighted)
                )
                .contextMenu { contextMenuContent }
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
        case .image:
            imageThumbnail
        case .video:
            videoThumbnail
        case .file:
            fileChip
        case .composite:
            compositeCard
        case .audio:
            HStack(spacing: 8) {
                Image(systemName: mediaSymbol)
                Text(mediaPlaceholderLabel)
            }
        }
    }

    private var compositeCard: some View {
        Button(action: onOpenCardDetail) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.message.payload?.title ?? item.message.content ?? "卡片消息")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isOutgoing ? .white : DesignTokens.Color.textPrimary)
                    .lineLimit(2)
                if let summary = buildSummary, !summary.isEmpty {
                    Text(summary)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(isOutgoing ? .white.opacity(0.8) : DesignTokens.Color.textSecondary)
                        .lineLimit(3)
                }
                if !mediaItems.isEmpty {
                    compositeGrid
                }
                if !fileItems.isEmpty {
                    compositeFileList
                }
                Divider()
                    .background(isOutgoing ? .white.opacity(0.3) : DesignTokens.Color.divider)
                Text("闪记卡片消息")
                    .font(.system(size: 11))
                    .foregroundStyle(isOutgoing ? .white.opacity(0.6) : DesignTokens.Color.textSecondary)
            }
            .frame(maxWidth: 260, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("messageCompositeCard")
    }

    private var compositeGrid: some View {
        let urls = mediaItems
        let count = min(urls.count, 9)
        let cols = count == 1 ? 1 : (count == 2 || count == 4 ? 2 : 3)
        let thumbSize: CGFloat = count == 1 ? 200 : 80

        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(thumbSize), spacing: 2), count: cols), spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                CachedThumbnailView(
                    objectName: urls[index],
                    fileRepository: fileRepository
                )
                .frame(width: thumbSize, height: thumbSize)
                .clipped()
                .background(Color.gray.opacity(0.15))
            }
        }
    }

    @ViewBuilder
    private var compositeFileList: some View {
        ForEach(fileItems, id: \.fileName) { fi in
            HStack(spacing: 6) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(isOutgoing ? .white.opacity(0.7) : DesignTokens.Color.textSecondary)
                Text(fi.fileName ?? "文件")
                    .font(.system(size: 12))
                    .foregroundStyle(isOutgoing ? .white.opacity(0.9) : DesignTokens.Color.textPrimary)
                    .lineLimit(1)
            }
        }
    }

    private var mediaItems: [String] {
        guard let items = item.message.payload?.items else { return [] }
        return items.compactMap { cardItem -> String? in
            let mt = cardItem.resolvedMediaType
            if mt == .image { return cardItem.mediaUrl }
            if mt == .video { return cardItem.thumbnailUrl ?? cardItem.mediaUrl }
            return nil
        }
    }

    private var fileItems: [CardItem] {
        guard let items = item.message.payload?.items else { return [] }
        return items.filter { $0.resolvedMediaType == .file }
    }

    private var buildSummary: String? {
        if let summary = item.message.payload?.summary, !summary.isEmpty { return summary }
        guard let items = item.message.payload?.items, !items.isEmpty else { return nil }
        let previews = items.prefix(3).map { ci -> String in
            switch ci.resolvedMediaType {
            case .image: return "[图片]"
            case .video: return "[视频]"
            case .audio: return "[语音]"
            case .file: return ci.fileName ?? "[文件]"
            default: return ci.content ?? ""
            }
        }
        let joined = previews.joined(separator: "、")
        return items.count > 3 ? "\(joined)等\(items.count)项" : joined
    }

    /// 长按菜单内容；按 mediaType 条件化展示「下载 / 外部打开」等。
    @ViewBuilder
    private var contextMenuContent: some View {
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

            Button {
                onForward()
            } label: {
                Label("转发", systemImage: "arrowshape.turn.up.right")
            }
            .accessibilityIdentifier("messageActionForward")

            if item.message.resolvedMediaType.isMediaAttachment {
                Button {
                    onDownloadMedia()
                } label: {
                    Label("下载到本地", systemImage: "arrow.down.circle")
                }
                .accessibilityIdentifier("messageActionDownload")

                Button {
                    onOpenExternally()
                } label: {
                    Label("用其他应用打开", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("messageActionOpenExternally")
            }

            Button {
                onLongPressForMultiSelect()
            } label: {
                Label("多选", systemImage: "checkmark.circle")
            }
            .accessibilityIdentifier("messageActionMultiSelect")
        }

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("删除", systemImage: "trash")
        }
        .accessibilityIdentifier("messageActionDelete")
    }

    private var imageThumbnail: some View {
        Button(action: onTapMediaAttachment) {
            CachedThumbnailView(
                objectName: item.message.thumbnailUrl ?? item.message.mediaUrl,
                fileRepository: fileRepository
            )
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var videoThumbnail: some View {
        Button(action: onTapMediaAttachment) {
            ZStack {
                CachedThumbnailView(
                    objectName: item.message.thumbnailUrl,
                    fileRepository: fileRepository
                )
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(radius: 4)
                if let dur = item.message.mediaDuration, dur > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(formatDuration(seconds: dur))
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.55))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .padding(6)
                        }
                    }
                }
            }
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var fileChip: some View {
        Button(action: onTapMediaAttachment) {
            HStack(spacing: 10) {
                Image(systemName: fileIconName)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.message.fileName ?? "未命名文件")
                        .font(DesignTokens.Typography.body)
                        .lineLimit(1)
                    if let size = item.message.fileSize, size > 0 {
                        Text(formatFileSize(size))
                            .font(DesignTokens.Typography.caption)
                            .opacity(0.85)
                    }
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: 240)
        }
        .buttonStyle(.plain)
    }

    private var placeholderImage: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "photo")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var placeholderVideo: some View {
        ZStack {
            Color.black.opacity(0.4)
            Image(systemName: "video")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var thumbnailURL: URL? {
        guard let resolver = mediaUrlResolver else { return nil }
        // 图片消息：thumbnailUrl 优先，回退到 mediaUrl。
        // 视频消息：仅 thumbnailUrl（视频原始 URL 不适合 AsyncImage）。
        switch item.message.resolvedMediaType {
        case .image:
            if let thumb = item.message.thumbnailUrl, !thumb.isEmpty {
                return resolver.resolve(thumb)
            }
            return resolver.resolve(item.message.mediaUrl)
        case .video:
            return resolver.resolve(item.message.thumbnailUrl)
        default:
            return nil
        }
    }

    private func formatDuration(seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
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

    private var fileIconName: String {
        let ext = (item.message.fileName ?? "")
            .components(separatedBy: ".").last?.lowercased() ?? ""
        switch ext {
        case "pdf": return "doc.richtext"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx": return "chart.bar.doc.horizontal"
        case "ppt", "pptx": return "doc.text.image"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        default: return "doc.fill"
        }
    }
}
