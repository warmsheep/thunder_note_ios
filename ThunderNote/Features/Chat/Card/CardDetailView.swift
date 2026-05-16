import SwiftUI

/// D2-I3-18 复合卡片详情页：全屏展示卡片标题、可选 summary、items 列表。
/// 与 Android `CardDetailActivity` 等价：
/// - 顶部展示标题（card.title 或 message.content 兜底）
/// - 中部展示 summary（可空）
/// - 下方按 item 类型渲染：图片走 image grid 缩略；视频带播放图标；文件走文件 chip；文本走纯文本气泡
/// - 点击 item 打开 `MediaPreviewView` 全屏预览
struct CardDetailView: View {
    let message: Message

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    @State private var previewRequest: MediaPreviewRequest?

    private var fileRepository: FileRepository { dependencies.fileRepository }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                    titleSection
                    if let summary = message.payload?.summary, !summary.isEmpty {
                        Text(summary)
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(DesignTokens.Color.textSecondary)
                    }
                    Divider()
                    itemsSection
                }
                .padding(DesignTokens.Spacing.large)
            }
            .navigationTitle("卡片详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(item: $previewRequest) { request in
                MediaPreviewView(
                    viewModel: MediaDownloadViewModel(
                        request: request,
                        fileRepository: dependencies.fileRepository
                    )
                )
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayTitle)
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Color.textPrimary)
            if let count = message.payload?.items?.count {
                Text("共 \(count) 项")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Color.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var itemsSection: some View {
        if let items = message.payload?.items, !items.isEmpty {
            VStack(spacing: DesignTokens.Spacing.medium) {
                ForEach(items) { item in
                    cardItemView(item)
                }
            }
        } else {
            Text("此卡片没有内容")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
    }

    private var displayTitle: String {
        if let title = message.payload?.title, !title.isEmpty { return title }
        if let content = message.content, !content.isEmpty { return content }
        return "未命名卡片"
    }

    @ViewBuilder
    private func cardItemView(_ item: CardItem) -> some View {
        switch item.resolvedMediaType {
        case .image:
            imageItem(item)
        case .video:
            videoItem(item)
        case .file:
            fileItem(item)
        case .audio:
            audioItem(item)
        case .text, .composite:
            textItem(item)
        }
    }

    private func imageItem(_ item: CardItem) -> some View {
        Button {
            openPreview(item, kind: .image)
        } label: {
            thumbnailView(item)
                .frame(maxWidth: .infinity, minHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cardItemImage")
    }

    private func videoItem(_ item: CardItem) -> some View {
        Button {
            openPreview(item, kind: .video)
        } label: {
            ZStack {
                thumbnailView(item)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cardItemVideo")
    }

    private func fileItem(_ item: CardItem) -> some View {
        Button {
            openPreview(item, kind: .other)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(DesignTokens.Color.brandPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName ?? "未命名文件")
                        .font(DesignTokens.Typography.body)
                    if let size = item.fileSize, size > 0 {
                        Text(formatFileSize(size))
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Color.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(DesignTokens.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cardItemFile")
    }

    private func audioItem(_ item: CardItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 24))
                .foregroundStyle(DesignTokens.Color.brandPrimary)
            Text(item.fileName ?? "[语音]")
                .font(DesignTokens.Typography.body)
            Spacer()
        }
        .padding(12)
        .background(DesignTokens.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func textItem(_ item: CardItem) -> some View {
        Text(item.content ?? "")
            .font(DesignTokens.Typography.body)
            .foregroundStyle(DesignTokens.Color.textPrimary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func thumbnailView(_ item: CardItem) -> some View {
        let objectName = item.thumbnailUrl ?? (item.resolvedMediaType == .image ? item.mediaUrl : nil)
        if let objectName, !objectName.isEmpty {
            CachedThumbnailView(
                objectName: objectName,
                fileRepository: dependencies.fileRepository
            )
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "photo")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func openPreview(_ item: CardItem, kind: MediaPreviewKind) {
        guard let objectName = item.mediaUrl, !objectName.isEmpty else { return }
        previewRequest = MediaPreviewRequest(
            kind: kind,
            objectName: objectName,
            title: item.fileName ?? displayTitle,
            fileName: item.fileName
        )
    }

    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
