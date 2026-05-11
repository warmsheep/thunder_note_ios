import SwiftUI

struct FlashNoteRowView: View {
    let note: FlashNote

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.medium) {
            Text(note.displayIcon)
                .font(.system(size: 28))
                .frame(width: 44, height: 44)
                .background(DesignTokens.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(note.displayTitle)
                        .font(DesignTokens.Typography.bodyEmphasized)
                        .foregroundStyle(DesignTokens.Color.textPrimary)
                        .lineLimit(1)
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.Color.brandPrimary)
                            .accessibilityIdentifier("flashNotePinIcon-\(note.id)")
                    }
                }
                if let preview = note.latestMessage, !preview.isEmpty {
                    Text(preview)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                        .lineLimit(1)
                } else if let tags = note.tags, !tags.isEmpty {
                    Text(tags)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("flashNoteRow-\(note.id)")
    }
}

#Preview {
    List {
        FlashNoteRowView(note: FlashNote(id: -1, inbox: true))
        FlashNoteRowView(note: FlashNote(id: 1, title: "工作", icon: "💼", latestMessage: "明天的会议要提前到 9 点", pinned: true))
        FlashNoteRowView(note: FlashNote(id: 2, title: "灵感", icon: "💡", tags: "学习"))
    }
}
