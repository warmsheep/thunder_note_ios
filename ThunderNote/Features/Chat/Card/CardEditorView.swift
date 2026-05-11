import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// D2-I3-19 卡片编辑器 SwiftUI 视图。
/// 入口：聊天页右上 + 闪记 FAB 卡片选项。提交成功后由调用方关闭并刷新会话。
struct CardEditorView: View {
    @StateObject var viewModel: CardEditorViewModel
    let onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var imagePicker = PhotosPickerHelper()
    @StateObject private var videoPicker = PhotosPickerHelper()
    @State private var presentImagePicker = false
    @State private var presentVideoPicker = false
    @State private var presentFilePicker = false
    @State private var presentTargetPicker = false

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                    titleSection
                    targetSection
                    itemsGrid
                    if viewModel.drafts.isEmpty {
                        emptyHint
                    }
                }
                .padding(DesignTokens.Spacing.large)
            }
            .navigationTitle("新建卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let ok = await viewModel.submit()
                            if ok {
                                onSubmitted()
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("发送")
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("cardEditorSubmit")
                }
            }
            .photosPicker(
                isPresented: $presentImagePicker,
                selection: $imagePicker.selectedItem,
                matching: .images
            )
            .photosPicker(
                isPresented: $presentVideoPicker,
                selection: $videoPicker.selectedItem,
                matching: .videos
            )
            .onChange(of: imagePicker.selectedItem) { newValue in
                guard newValue != nil else { return }
                Task {
                    if let url = await imagePicker.loadLocalURL(suggestedExtension: "jpg") {
                        viewModel.appendImage(localURL: url)
                    }
                    imagePicker.reset()
                }
            }
            .onChange(of: videoPicker.selectedItem) { newValue in
                guard newValue != nil else { return }
                Task {
                    if let url = await videoPicker.loadLocalURL(suggestedExtension: "mp4") {
                        viewModel.appendVideo(localURL: url)
                    }
                    videoPicker.reset()
                }
            }
            .fileImporter(
                isPresented: $presentFilePicker,
                allowedContentTypes: [.data, .pdf, .text, .image, .audiovisualContent],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let needsScope = url.startAccessingSecurityScopedResource()
                    let copied = copyToTemp(url: url)
                    if needsScope { url.stopAccessingSecurityScopedResource() }
                    if let copied { viewModel.appendFile(localURL: copied) }
                case .failure(let error):
                    viewModel.transientMessage = error.localizedDescription
                }
            }
            .alert(
                "提示",
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
    }

    // MARK: - 各 section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("标题")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Color.textSecondary)
            TextField("请输入卡片标题", text: $viewModel.title, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .accessibilityIdentifier("cardEditorTitleField")
            HStack {
                Spacer()
                Text("\(viewModel.titleCount) / \(CardEditorViewModel.maxTitleLength)")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Color.textSecondary)
            }
        }
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("发送到")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Color.textSecondary)
            HStack(spacing: 8) {
                targetChip(title: "当前会话", isSelected: viewModel.target != .inbox) {
                    if case .currentConversation = viewModel.target { return }
                }
                targetChip(title: "收集箱", isSelected: viewModel.target == .inbox) {
                    viewModel.target = .inbox
                }
            }
        }
    }

    private func targetChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignTokens.Typography.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? DesignTokens.Color.brandPrimary : DesignTokens.Color.surface)
                )
                .foregroundStyle(isSelected ? Color.white : DesignTokens.Color.textPrimary)
        }
        .buttonStyle(.plain)
    }

    private var itemsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("媒体（最多 \(CardEditorViewModel.maxItems) 项）")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Color.textSecondary)
                Spacer()
                Menu {
                    Button("从相册选图片") { presentImagePicker = true }
                    Button("从相册选视频") { presentVideoPicker = true }
                    Button("选择文件") { presentFilePicker = true }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(DesignTokens.Color.brandPrimary)
                }
                .disabled(!viewModel.canAddMore)
                .accessibilityIdentifier("cardEditorAddButton")
            }

            if !viewModel.drafts.isEmpty {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(viewModel.drafts.enumerated()), id: \.element.id) { index, draft in
                        draftCell(draft: draft, index: index)
                    }
                }
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.Color.textSecondary)
            Text("还没有添加任何媒体")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func draftCell(draft: CardEditorViewModel.Draft, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Image(systemName: iconName(for: draft))
                    .font(.system(size: 28))
                    .foregroundStyle(DesignTokens.Color.brandPrimary)
                Text(draft.displayName)
                    .font(DesignTokens.Typography.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .padding(8)
            .background(DesignTokens.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                viewModel.removeDraft(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.black.opacity(0.6))
                    .padding(4)
            }
            .accessibilityIdentifier("cardEditorRemove-\(index)")
        }
    }

    private func iconName(for draft: CardEditorViewModel.Draft) -> String {
        switch draft.kind {
        case .image: return "photo"
        case .video: return "play.rectangle"
        case .file:  return "doc"
        }
    }

    private func copyToTemp(url: URL) -> URL? {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("tn-cardedit-\(UUID().uuidString)-\(url.lastPathComponent)")
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
