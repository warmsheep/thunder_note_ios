import SwiftUI

/// D2-I2-14 全屏快速捕获文本编辑器。
/// 入口：`FlashNoteListView` 的 FAB 菜单 → 文本入口。
/// 行为：
/// - 全屏 sheet（`.fullScreenCover` 或 `NavigationStack` 包裹的 sheet）。
/// - 取消 / 保存按钮放在 `NavigationBar` 顶部。
/// - 富文本工具栏 4 项：粗体 / 斜体 / 引用 / 待办，分别围绕选区或行首插入 Markdown token。
/// - 保存成功后由 `onSubmitted` 回调通知上层（`FlashNoteListViewModel.updateInboxPreviewLocally`
///   也会被 AppDependencies 自动调用，无需上层重复触发）。
struct QuickCaptureTextEditorView: View {
    @StateObject var viewModel: QuickCaptureTextEditorViewModel
    let onSubmitted: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RichTextEditor(
                    text: $viewModel.text,
                    selectedRange: $viewModel.selectedRange,
                    initiallyFocused: true
                )
                .padding(.horizontal, DesignTokens.Spacing.medium)
                .padding(.vertical, DesignTokens.Spacing.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                toolbar
                    .padding(.horizontal, DesignTokens.Spacing.medium)
                    .padding(.vertical, DesignTokens.Spacing.small)
                    .background(DesignTokens.Color.surface)
            }
            .navigationTitle("快速捕获")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { onDismiss() }
                        .accessibilityIdentifier("quickCaptureCancelButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        Task {
                            let ok = await viewModel.save()
                            if ok { onSubmitted() }
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("quickCaptureSaveButton")
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

    private var toolbar: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            toolbarButton(
                systemImage: "bold",
                identifier: "quickCaptureFormatBold",
                action: { viewModel.toggleBold() }
            )
            toolbarButton(
                systemImage: "italic",
                identifier: "quickCaptureFormatItalic",
                action: { viewModel.toggleItalic() }
            )
            toolbarButton(
                systemImage: "text.quote",
                identifier: "quickCaptureFormatQuote",
                action: { viewModel.insertQuote() }
            )
            toolbarButton(
                systemImage: "checklist",
                identifier: "quickCaptureFormatTodo",
                action: { viewModel.insertTodo() }
            )
            Spacer()
            if viewModel.isSubmitting {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toolbarButton(
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(DesignTokens.Color.brandPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
