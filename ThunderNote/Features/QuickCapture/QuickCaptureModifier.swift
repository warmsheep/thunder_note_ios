import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// D2-I2-13 / D2-I2-14 快速捕获主链：把 6 入口菜单 + 文本编辑器 sheet +
/// 图片 / 视频 PhotosPicker + 文件 fileImporter + 相机 sheet + 卡片编辑器
/// 全部封装成一个 ViewModifier，挂在 `FlashNoteListView` 上。
///
/// 这样列表主体不会被快速捕获相关的 7 个 sheet / 4 个 picker / 2 个
/// onChange 全部塞满，可读性更好。
struct QuickCaptureModifier: ViewModifier {
    @Binding var presentMenu: Bool
    @Binding var presentText: Bool
    @Binding var presentImagePicker: Bool
    @Binding var presentVideoPicker: Bool
    @Binding var presentFilePicker: Bool
    @Binding var presentCamera: Bool
    @Binding var presentCard: Bool
    @ObservedObject var imagePickerHelper: PhotosPickerHelper
    @ObservedObject var videoPickerHelper: PhotosPickerHelper
    let dependencies: AppDependencies
    let flashNoteListViewModel: FlashNoteListViewModel

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "快速捕获",
                isPresented: $presentMenu,
                titleVisibility: .visible
            ) {
                Button("文本") {
                    presentText = true
                }
                .accessibilityIdentifier("quickCaptureMenuText")
                Button("图片") {
                    GestureLockBypass.register(); presentImagePicker = true
                }
                .accessibilityIdentifier("quickCaptureMenuImage")
                Button("视频") {
                    GestureLockBypass.register(); presentVideoPicker = true
                }
                .accessibilityIdentifier("quickCaptureMenuVideo")
                Button("文件") {
                    GestureLockBypass.register(); presentFilePicker = true
                }
                .accessibilityIdentifier("quickCaptureMenuFile")
                Button("拍照") {
                    if CameraCaptureView.isAvailable {
                        GestureLockBypass.register(); presentCamera = true
                    } else {
                        flashNoteListViewModel.transientMessage = "当前设备不支持相机"
                    }
                }
                .accessibilityIdentifier("quickCaptureMenuCamera")
                Button("卡片") {
                    presentCard = true
                }
                .accessibilityIdentifier("quickCaptureMenuCard")
                Button("取消", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $presentText) {
                QuickCaptureTextEditorView(
                    viewModel: dependencies.makeQuickCaptureTextEditorViewModel(),
                    onSubmitted: { presentText = false },
                    onDismiss: { presentText = false }
                )
            }
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
                        _ = await dependencies.submitQuickCaptureImage(localURL: url)
                    }
                    imagePickerHelper.reset()
                }
            }
            .onChange(of: videoPickerHelper.selectedItem) { newValue in
                guard newValue != nil else { return }
                Task {
                    if let url = await videoPickerHelper.loadLocalURL(suggestedExtension: "mp4") {
                        _ = await dependencies.submitQuickCaptureVideo(localURL: url)
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
            .sheet(isPresented: $presentCamera) {
                CameraCaptureView(
                    onPicked: { url in
                        presentCamera = false
                        Task { _ = await dependencies.submitQuickCaptureImage(localURL: url) }
                    },
                    onCancel: { presentCamera = false }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $presentCard) {
                CardEditorView(
                    viewModel: CardEditorViewModel(
                        target: .inbox,
                        attachmentService: dependencies.attachmentSendingService,
                        messageRepository: dependencies.messageRepository,
                        session: dependencies.session
                    ),
                    onSubmitted: {
                        // 卡片入口预览统一刷为「[卡片]」，与 Android 行为对齐。
                        flashNoteListViewModel.updateInboxPreviewLocally("[卡片]")
                    }
                )
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
                flashNoteListViewModel.transientMessage = "无法读取所选文件"
                return
            }
            Task { _ = await dependencies.submitQuickCaptureFile(localURL: copied) }
        case .failure(let error):
            flashNoteListViewModel.transientMessage = error.localizedDescription
        }
    }

    private func copyToTemp(url: URL) -> URL? {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("tn-quick-\(UUID().uuidString)-\(url.lastPathComponent)")
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
}
