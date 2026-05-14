import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// 三模式公共聊天页骨架。
struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    let onAppearAutoUnhide: (() async -> Void)?

    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var favoriteRegistry: FavoriteIdRegistry
    @State private var scrollToken: UUID? = nil

    @StateObject private var imagePickerHelper = PhotosPickerHelper()
    @StateObject private var videoPickerHelper = PhotosPickerHelper()
    @StateObject private var recordingHelper = ChatRecordingHelper()
    @State private var presentImagePicker = false
    @State private var presentVideoPicker = false
    @State private var presentFilePicker = false
    @State private var presentCameraCapture = false
    @State private var presentCardEditor = false
    @State private var mediaPreviewRequest: MediaPreviewRequest?
    @State private var cardDetailMessage: Message? = nil
    @State private var mergeTitle: String = ""
    /// 录音长按手势的拖动偏移；y 大于 -60 时进入「上滑取消」区域。
    @State private var recordingDragOffset: CGSize = .zero
    /// 当前是否处于录音中（手指未抬起）。
    @State private var isRecordingActive: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isMultiSelectMode {
                multiSelectTopBar
            }
            ZStack(alignment: .bottom) {
                content
                if isRecordingActive {
                    RecordingOverlay(
                        elapsed: recordingHelper.elapsed,
                        levels: recordingHelper.levels,
                        isCancelArea: isInCancelArea
                    )
                    .padding(.bottom, 80)
                    .transition(.opacity)
                }
            }
            inputArea
        }
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("chatView-\(viewModel.key.descriptor)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.isMultiSelectMode {
                    Menu {
                        Button {
                            presentCardEditor = true
                        } label: {
                            Label("新建卡片", systemImage: "rectangle.stack.badge.plus")
                        }
                        .accessibilityIdentifier("chatToolbarNewCard")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            await viewModel.onAppear()
            scrollToken = UUID()
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
        .sheet(isPresented: $presentCameraCapture) {
            CameraCaptureView(
                onPicked: { url in
                    presentCameraCapture = false
                    Task { await viewModel.sendImage(localURL: url) }
                },
                onCancel: {
                    presentCameraCapture = false
                }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $mediaPreviewRequest) { request in
            MediaPreviewView(
                viewModel: MediaDownloadViewModel(
                    request: request,
                    fileRepository: dependencies.fileRepository
                )
            )
        }
        .sheet(isPresented: $presentCardEditor) {
            CardEditorView(
                viewModel: CardEditorViewModel(
                    target: .currentConversation(viewModel.key),
                    attachmentService: dependencies.attachmentSendingService,
                    messageRepository: dependencies.messageRepository,
                    session: dependencies.session
                ),
                onSubmitted: {
                    Task { await viewModel.refresh() }
                }
            )
        }
        .sheet(item: $cardDetailMessage) { msg in
            CardDetailView(
                message: msg,
                mediaUrlResolver: dependencies.mediaUrlResolver
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
        .alert("合并为卡片", isPresented: $viewModel.presentMergeSheet) {
            TextField("卡片标题", text: $mergeTitle)
            Button("取消", role: .cancel) { mergeTitle = "" }
            Button("合并") {
                let t = mergeTitle
                mergeTitle = ""
                Task { await viewModel.mergeSelected(title: t) }
            }
        } message: {
            Text("将所选 \(viewModel.selectedRemoteIds.count) 条消息合并为一张卡片")
        }
    }

    @ViewBuilder
    private var inputArea: some View {
        ChatInputBar(
            text: $viewModel.inputText,
            isSending: viewModel.isSending,
            isRecordingActive: $isRecordingActive,
            onSend: {
                Task { await viewModel.sendText() }
            },
            onPickImage: { GestureLockBypass.register(); presentImagePicker = true },
            onPickVideo: { GestureLockBypass.register(); presentVideoPicker = true },
            onPickFile: { GestureLockBypass.register(); presentFilePicker = true },
            onPickCamera: {
                if CameraCaptureView.isAvailable {
                    GestureLockBypass.register(); presentCameraCapture = true
                } else {
                    viewModel.transientMessage = "当前设备不支持相机"
                }
            },
            onRecordingDragChanged: { offset in
                recordingDragOffset = offset
            },
            onRecordingStart: { startRecording() },
            onRecordingFinish: { finishRecording() }
        )
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
                prependAnchorMessageId: viewModel.prependAnchorMessageId,
                mediaUrlResolver: dependencies.mediaUrlResolver,
                fileRepository: dependencies.fileRepository,
                isMultiSelectMode: viewModel.isMultiSelectMode,
                selectedRemoteIds: viewModel.selectedRemoteIds,
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
                    if item.message.resolvedMediaType == .composite {
                        cardDetailMessage = item.message
                    } else {
                        handleMediaTap(item)
                    }
                },
                onReachedTop: {
                    Task { await viewModel.loadMoreOlder() }
                },
                onScrollTargetConsumed: {
                    viewModel.didConsumeScrollTarget()
                },
                onPrependAnchorConsumed: {
                    viewModel.didConsumePrependAnchor()
                },
                onLongPressForMultiSelect: { item in
                    viewModel.enterMultiSelect(initial: item)
                },
                onToggleSelection: { item in
                    viewModel.toggleSelection(item)
                },
                onDownloadMedia: { item in
                    Task { await downloadMedia(item) }
                },
                onOpenExternally: { item in
                    handleMediaTap(item) // 走预览 sheet，sheet 内的「分享」按钮会调用 UIActivityViewController
                },
                onForward: { item in
                    handleForward(item)
                },
                onOpenCardDetail: { item in
                    cardDetailMessage = item.message
                },
                scrollToken: $scrollToken
            )
        }
    }

    /// D2-I3-16 多选 toolbar：顶部展示选中数 + 退出 + 删除 + 合并。
    private var multiSelectTopBar: some View {
        HStack {
            Button {
                viewModel.exitMultiSelect()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignTokens.Color.textPrimary)
            }
            .accessibilityIdentifier("multiSelectExit")
            Spacer()
            Text("已选 \(viewModel.selectedRemoteIds.count)")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.textPrimary)
            Spacer()
            HStack(spacing: 16) {
                Button {
                    viewModel.openMergeSheet()
                } label: {
                    Image(systemName: "rectangle.stack")
                }
                .disabled(viewModel.selectedRemoteIds.isEmpty)
                .accessibilityIdentifier("multiSelectMerge")

                Button(role: .destructive) {
                    Task { await viewModel.deleteSelected() }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.selectedRemoteIds.isEmpty)
                .accessibilityIdentifier("multiSelectDelete")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .padding(.vertical, DesignTokens.Spacing.small)
        .background(DesignTokens.Color.surface)
    }

    // MARK: - 长按录音手势辅助

    /// 上滑超过 60pt 视为进入「取消区域」。
    private var isInCancelArea: Bool {
        recordingDragOffset.height < -60
    }

    private func startRecording() {
        guard !isRecordingActive else { return }
        Task {
            let ok = await recordingHelper.start()
            if ok {
                isRecordingActive = true
            } else if case .failed(let message) = recordingHelper.state {
                viewModel.transientMessage = message
                recordingHelper.reset()
            }
        }
    }

    private func finishRecording() {
        guard isRecordingActive else { return }
        let inCancel = isInCancelArea
        if inCancel {
            recordingHelper.cancel()
        } else {
            recordingHelper.stopAndKeep()
            if case .finished(let url, _) = recordingHelper.state {
                Task { await viewModel.sendFile(localURL: url) }
            }
        }
        isRecordingActive = false
        recordingDragOffset = .zero
        recordingHelper.reset()
    }

    // MARK: - 媒体相关

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

    /// D2-I3-15 下载到本地：缓存后复制到 Documents/闪记/ 并用原始文件名。
    private func downloadMedia(_ item: ChatMessageItem) async {
        guard let objectName = item.message.mediaUrl, !objectName.isEmpty else {
            viewModel.transientMessage = "没有可下载的文件"
            return
        }
        do {
            let cachedURL = try await dependencies.fileRepository.download(objectName: objectName)
            let fileName = item.message.fileName ?? objectName.components(separatedBy: "/").last ?? "file"
            let downloadsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("闪记", isDirectory: true)
            try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
            let destination = uniqueURL(in: downloadsDir, fileName: fileName)
            try FileManager.default.copyItem(at: cachedURL, to: destination)
            viewModel.transientMessage = "已保存到：闪记/\(destination.lastPathComponent)"
        } catch {
            viewModel.transientMessage = "下载失败：\(error.localizedDescription)"
        }
    }

    private func uniqueURL(in directory: URL, fileName: String) -> URL {
        var target = directory.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: target.path) { return target }
        let ext = (fileName as NSString).pathExtension
        let name = (fileName as NSString).deletingPathExtension
        var i = 1
        repeat {
            let newName = ext.isEmpty ? "\(name)(\(i))" : "\(name)(\(i)).\(ext)"
            target = directory.appendingPathComponent(newName)
            i += 1
        } while FileManager.default.fileExists(atPath: target.path)
        return target
    }

    /// D2-I3-15 转发：文件类消息先下载再拷贝文件到剪贴板；文本直接拷贝文本。
    private func handleForward(_ item: ChatMessageItem) {
        if item.message.resolvedMediaType == .text {
            UIPasteboard.general.string = item.message.content
            viewModel.transientMessage = "已复制文本，可粘贴到其他会话"
        } else if item.message.resolvedMediaType.isMediaAttachment {
            guard let objectName = item.message.mediaUrl, !objectName.isEmpty else {
                viewModel.transientMessage = "没有可转发的内容"
                return
            }
            let fileName = item.message.fileName ?? "file"
            Task {
                do {
                    let cachedURL = try await dependencies.fileRepository.download(objectName: objectName)
                    UIPasteboard.general.url = cachedURL
                    viewModel.transientMessage = "已复制「\(fileName)」，可粘贴到其他会话"
                } catch {
                    viewModel.transientMessage = "转发失败：\(error.localizedDescription)"
                }
            }
        } else {
            viewModel.transientMessage = "没有可转发的内容"
        }
    }

    private func handleFilePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let needsScope = url.startAccessingSecurityScopedResource()
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

