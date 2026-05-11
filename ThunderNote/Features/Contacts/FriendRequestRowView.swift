import SwiftUI

struct FriendRequestRowView: View {
    let request: FriendRequest
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            ZStack {
                Circle()
                    .fill(DesignTokens.Color.surface)
                    .frame(width: 44, height: 44)
                Text(initials)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignTokens.Color.brandPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(request.displayName)
                    .font(DesignTokens.Typography.bodyEmphasized)
                    .lineLimit(1)
                Text("请求添加你为好友")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Color.textSecondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button("拒绝") { onReject() }
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Color.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DesignTokens.Color.divider, lineWidth: 1)
                    )
                    .accessibilityIdentifier("friendRequestReject-\(request.requestId)")

                Button("接受") { onAccept() }
                    .font(DesignTokens.Typography.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DesignTokens.Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier("friendRequestAccept-\(request.requestId)")
            }
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("friendRequestRow-\(request.requestId)")
    }

    private var initials: String {
        let source = request.displayName
        guard let first = source.first else { return "?" }
        return String(first).uppercased()
    }
}
