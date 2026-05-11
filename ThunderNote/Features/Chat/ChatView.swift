import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 三模式公共聊天页骨架。
struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    let onAppearAutoUnhide: (() async -> Void)?

    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var favoriteRegistry: FavoriteIdRegistry
    @State private var scrollToken: UUID? = nil

    @StateObject private var imagePickerHelper = PhotosPickerHelper()
    @StateObject private var videoPickerHelper = PhotosPickerHelper()
    @State private var presentImagePicker = false
    @State private var presentVideoPicker = false
    @State private var presentFilePicker = false
    @State private var mediaPreviewRequest: MediaPreviewRequest?

    var body: some View {
        VStack(spacing: 0) {
            content
            ChatInputBar(
                text: $viewModel.inputText,
                isSending: viewModel.isSending,
                onSend: {
                    Task { await viewModel.sendText() }
                },
                onPickImage: { presentImagePicker = true },
                onPickVideo: { presentVideoPicker = true },
                onPickFile: { presentFilePicker = true }
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
        .photosPicker(
            isPresented: $presentImagePicker,
            selection: $imagePickerHelper.selectedItem,
            matching: .images
        )
        .photosPicker(
            isPresented: $presentVideoPicker,
            selection: $videoPickerHelper.selectedItem,
            matching: .videos
        )
        .onChange(of: imagePickerHelper.selectedItem) { newValue in
            guard newValue != nil else { return }
            Task {
                if let url = await imagePickerHelper.loadLocalURL(suggestedExtension: "jpg") {
                    await viewModel.sendImage(localURL: url)
                }
                imagePickerHelper.reset()
            }
        }
        .onChange(of: videoPickerHelper.selectedItem) { newValue in
            guard newValue != nil else { return }
            Task {
                if let url = await videoPickerHelper.loadLocalURL(suggestedExtension: "mp4") {
                    await viewModel.sendVideo(localURL: url)
                }
                videoPickerHelper.reset()
            }
        }
        .fileImporter(
            isPresented: $presentFilePicker,
            allowedContentTypes: [.data, .pdf, .text, .plainText, .image, .audiovisualContent, .compositeContent],
            allowsMultipleSelection: false
        ) { result in
            handleFilePickerResult(result)
        }
        .sheet(item: $mediaPreviewRequest) { request in
            MediaPreviewView(
                viewModel: MediaDownloadViewModel(
                    request: request,
                    fileRepository: dependencies.fileRepository
                )
            )
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
                highlightedMessageId: viewModel.highlightedMessageId,
                scrollTargetMessageId: viewModel.scrollTargetMessageId,
                mediaUrlResolver: dependencies.mediaUrlResolver,
                isFavorited: { item in
                    guard let remoteId = item.remoteId else { return false }
                    return favoriteRegistry.contains(remoteId)
                },
                onCopy: { item in
                    UIPasteboard.general.string = item.message.content ?? ""
                },
                onDelete: { item in
                    Task { await viewModel.delete(item) }
                },
                onRetry: { item in
                    Task { await viewModel.retry(item) }
                },
                onToggleFavorite: { item in
                    Task { await viewModel.toggleFavorite(item) }
                },
                onTapMediaAttachment: { item in
                    handleMediaTap(item)
                },
                onReachedTop: {
                    Task { await viewModel.loadMoreOlder() }
                },
                onScrollTargetConsumed: {
                    viewModel.didConsumeScrollTarget()
                },
                scrollToken: $scrollToken
            )
        }
    }

    private func handleMediaTap(_ item: ChatMessageItem) {
        guard let objectName = item.message.mediaUrl, !objectName.isEmpty else { return }
        let kind = MediaPreviewKind.resolve(
            mediaType: item.message.resolvedMediaType,
            fileName: item.message.fileName
        )
        mediaPreviewRequest = MediaPreviewRequest(
            kind: kind,
            objectName: objectName,
            title: item.message.fileName ?? "预览",
            fileName: item.message.fileName
        )
    }

    private func handleFilePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // fileImporter 返回的 URL 是 security scoped；需要 startAccessing。
            let needsScope = url.startAccessingSecurityScopedResource()
            // 立刻拷到 tmp 摆脱 scope 限制，避免上传时失败。
            let copied = copyToTemp(url: url)
            if needsScope { url.stopAccessingSecurityScopedResource() }
            guard let copied else {
                viewModel.transientMessage = "无法读取所选文件"
                return
            }
            Task { await viewModel.sendFile(localURL: copied) }
        case .failure(let error):
            viewModel.transientMessage = error.localizedDescription
        }
    }

    private func copyToTemp(url: URL) -> URL? {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("tn-doc-\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
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
