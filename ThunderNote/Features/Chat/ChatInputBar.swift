import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isSending: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: DesignTokens.Spacing.small) {
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
            .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("chatInputSendButton")
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
    }
}
