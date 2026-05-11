import SwiftUI

struct FlashNoteEditSheet: View {
    @StateObject var viewModel: FlashNoteEditViewModel
    let onSaved: (FlashNote) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("请输入闪记标题", text: $viewModel.title)
                        .focused($titleFocused)
                        .accessibilityIdentifier("flashNoteEditTitleField")
                }

                Section("图标") {
                    IconChipGrid(selected: $viewModel.icon)
                        .padding(.vertical, DesignTokens.Spacing.xSmall)
                }

                Section("合集") {
                    TextField("可选：合集名称", text: $viewModel.tags)
                        .accessibilityIdentifier("flashNoteEditTagsField")
                }

                if let message = viewModel.errorMessage {
                    Section {
                        Text(message)
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("flashNoteEditErrorText")
                    }
                }
            }
            .navigationTitle(viewModel.isEditing ? "编辑闪记" : "新建闪记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isEditing ? "保存" : "创建") {
                        Task {
                            if let note = await viewModel.submit() {
                                onSaved(note)
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("flashNoteEditSubmitButton")
                }
            }
            .onAppear {
                if !viewModel.isEditing { titleFocused = true }
            }
        }
    }
}
