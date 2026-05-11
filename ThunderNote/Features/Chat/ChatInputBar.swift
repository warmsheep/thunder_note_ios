import SwiftUI

/// 聊天页底部输入栏。
/// - 文本输入 + 发送按钮
/// - 「+」按钮弹出 sheet：拍照 / 图片 / 视频 / 文件
/// - 长按麦克风按钮启动录音；DragGesture 上滑 ≥ 60pt 进入「取消区」（颜色变红）；
///   松手时调用 `onRecordingFinish`，由 ChatView 决定 stopAndKeep / cancel。
struct ChatInputBar: View {
    @Binding var text: String
    let isSending: Bool
    @Binding var isRecordingActive: Bool
    let onSend: () -> Void
    let onPickImage: () -> Void
    let onPickVideo: () -> Void
    let onPickFile: () -> Void
    let onPickCamera: () -> Void
    let onRecordingDragChanged: (CGSize) -> Void
    let onRecordingStart: () -> Void
    let onRecordingFinish: () -> Void

    @State private var showAttachmentSheet = false

    var body: some View {
        HStack(alignment: .bottom, spacing: DesignTokens.Spacing.small) {
            Button {
                showAttachmentSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(DesignTokens.Color.brandPrimary)
            }
            .disabled(isSending || isRecordingActive)
            .accessibilityIdentifier("chatInputAttachButton")

            TextField(
                "输入消息",
                text: $text,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...5)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesignTokens.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
            .accessibilityIdentifier("chatInputField")
            .disabled(isRecordingActive)

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recordButton
            } else {
                sendButton
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .padding(.vertical, DesignTokens.Spacing.small)
        .background(DesignTokens.Color.background)
        .overlay(
            Rectangle()
                .fill(DesignTokens.Color.divider)
                .frame(height: 0.5),
            alignment: .top
        )
        .confirmationDialog("发送附件", isPresented: $showAttachmentSheet, titleVisibility: .hidden) {
            Button("拍照") { onPickCamera() }
                .accessibilityIdentifier("chatInputPickCamera")
            Button("图片") { onPickImage() }
                .accessibilityIdentifier("chatInputPickImage")
            Button("视频") { onPickVideo() }
                .accessibilityIdentifier("chatInputPickVideo")
            Button("文件") { onPickFile() }
                .accessibilityIdentifier("chatInputPickFile")
            Button("取消", role: .cancel) { }
        }
    }

    private var sendButton: some View {
        Button {
            onSend()
        } label: {
            if isSending {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .frame(width: 36, height: 36)
                    .background(DesignTokens.Color.brandPrimary.opacity(0.7))
                    .clipShape(Circle())
            } else {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.white)
                    .background(DesignTokens.Color.brandPrimary)
                    .clipShape(Circle())
            }
        }
        .disabled(isSending)
        .accessibilityIdentifier("chatInputSendButton")
    }

    /// D2-I3-11 录音按钮：长按 + DragGesture 组合。
    /// - 长按超过 0.2s 触发 `onRecordingStart`。
    /// - 拖动期间持续上报 offset，让上层判断是否在「取消区」。
    /// - 松手时（gesture.onEnded）触发 `onRecordingFinish`。
    private var recordButton: some View {
        Image(systemName: isRecordingActive ? "mic.fill" : "mic")
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 36, height: 36)
            .foregroundStyle(.white)
            .background(isRecordingActive ? Color.red : DesignTokens.Color.brandPrimary)
            .clipShape(Circle())
            .accessibilityIdentifier("chatInputRecordButton")
            .gesture(recordingGesture)
    }

    private var recordingGesture: some Gesture {
        // 用 `LongPressGesture` 触发开始，串联 `DragGesture` 跟踪偏移。
        LongPressGesture(minimumDuration: 0.2)
            .onEnded { _ in
                onRecordingStart()
            }
            .simultaneously(with:
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if isRecordingActive {
                            onRecordingDragChanged(value.translation)
                        }
                    }
                    .onEnded { _ in
                        if isRecordingActive {
                            onRecordingFinish()
                        }
                    }
            )
    }
}
