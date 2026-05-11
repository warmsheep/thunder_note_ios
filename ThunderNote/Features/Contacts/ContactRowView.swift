import SwiftUI

struct ContactRowView: View {
    let contact: ContactUser

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(contact.displayName)
                        .font(DesignTokens.Typography.bodyEmphasized)
                        .foregroundStyle(DesignTokens.Color.textPrimary)
                        .lineLimit(1)
                    if contact.relationStatus.isPending {
                        Text(pendingTagText)
                            .font(DesignTokens.Typography.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignTokens.Color.brandPrimary.opacity(0.18))
                            .foregroundStyle(DesignTokens.Color.brandPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                if let preview = contact.latestMessage, !preview.isEmpty {
                    Text(preview)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("contactRow-\(contact.userId)")
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(DesignTokens.Color.surface)
                .frame(width: 44, height: 44)
            Text(initials)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignTokens.Color.brandPrimary)
        }
    }

    private var initials: String {
        let source = contact.displayName
        guard let first = source.first else { return "?" }
        return String(first).uppercased()
    }

    private var pendingTagText: String {
        switch contact.relationStatus {
        case .pendingSent: return "等待对方同意"
        case .pendingReceived: return "等待我同意"
        default: return ""
        }
    }
}
