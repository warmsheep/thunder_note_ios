import SwiftUI

/// 「发送到…」目标选择面板：闪记（含收集箱）+ 联系人。
/// 当前 MVP 仅支持把 **文本** 条目落到对应会话；图片 / 视频 / 文件条目先展示在列表里，
/// 真正发送需要 D2-I3-08~13 的媒体消息链路接入，本次会话先做文本 + 占位提示。
@MainActor
struct ShareTargetPickerSheet: View {
    let entry: ShareInboxEntry
    let flashNotes: [FlashNote]
    let contacts: [ContactUser]
    let onSubmitText: @MainActor (ConversationKey) async -> Bool
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var transientMessage: String?
    @State private var isWorking: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section("预览") {
                    Text(entry.previewLabel())
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                        .lineLimit(3)
                }

                if entry.isText {
                    Section("发送到闪记") {
                        ForEach(flashNotes) { note in
                            TargetRow(
                                icon: note.displayIcon,
                                title: note.displayTitle,
                                isDisabled: isWorking
                            ) {
                                submit(key: .flashNote(note.id))
                            }
                        }
                    }
                    if !contacts.isEmpty {
                        Section("发送到联系人") {
                            ForEach(contacts) { contact in
                                TargetRow(
                                    icon: "👤",
                                    title: contact.displayName,
                                    isDisabled: isWorking
                                ) {
                                    submit(key: .peer(contact.userId))
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        Text("多媒体条目将在图片 / 视频 / 文件消息链路接入后自动发送；当前可在主 App 内按需手动处理。")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Color.textSecondary)
                    }
                }
            }
            .navigationTitle("发送到…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("跳过") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
            .alert(
                "发送失败",
                isPresented: Binding(
                    get: { transientMessage != nil },
                    set: { if !$0 { transientMessage = nil } }
                )
            ) {
                Button("好") { transientMessage = nil }
            } message: {
                Text(transientMessage ?? "")
            }
        }
    }

    private func submit(key: ConversationKey) {
        Task { @MainActor in
            isWorking = true
            let ok = await onSubmitText(key)
            isWorking = false
            if ok {
                dismiss()
            } else {
                transientMessage = "发送失败，请稍后再试"
            }
        }
    }
}

private struct TargetRow: View {
    let icon: String
    let title: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(icon).font(.system(size: 22))
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
    }
}
