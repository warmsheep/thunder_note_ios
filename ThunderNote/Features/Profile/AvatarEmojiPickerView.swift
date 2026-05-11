import SwiftUI

/// D2-I6-03 头像 emoji 选择器。
///
/// 与 Android `EditProfileFragment.showEmojiPicker()` + `R.array.profile_avatar_emojis` 对齐：
/// - 固定 12 个 emoji，4 列网格；
/// - 选中态使用主色软背景圆形高亮；
/// - 点确定回调 emoji 字符串给上层（由上层走 `PUT /api/users/avatar`）。
struct AvatarEmojiPickerView: View {
    /// 与 Android `profile_avatar_emojis` 完全一致。新增 / 调整必须同步 Android 资源。
    static let avatarEmojis: [String] = [
        "💼", "📚", "❤️", "🌟",
        "🎯", "🚀", "🎨", "🎵",
        "📷", "🍕", "⚽", "😊"
    ]

    let initialEmoji: String?
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    @State private var showSelectHint: Bool = false

    init(initialEmoji: String?, onConfirm: @escaping (String) -> Void) {
        self.initialEmoji = initialEmoji
        self.onConfirm = onConfirm
        _selected = State(initialValue: Self.avatarEmojis.contains(initialEmoji ?? "") ? initialEmoji : nil)
    }

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 12),
        count: 4
    )

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Self.avatarEmojis, id: \.self) { emoji in
                        emojiCell(emoji)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                if showSelectHint {
                    Text("请先选择一个头像")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.red)
                        .accessibilityIdentifier("avatarEmojiHint")
                }

                Spacer(minLength: 0)
            }
            .navigationTitle("选择头像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .accessibilityIdentifier("avatarEmojiCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        guard let emoji = selected else {
                            showSelectHint = true
                            return
                        }
                        onConfirm(emoji)
                        dismiss()
                    }
                    .accessibilityIdentifier("avatarEmojiConfirm")
                }
            }
        }
    }

    private func emojiCell(_ emoji: String) -> some View {
        let isSelected = (emoji == selected)
        return Button {
            selected = emoji
            showSelectHint = false
        } label: {
            Text(emoji)
                .font(.system(size: 28))
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(isSelected ? DesignTokens.Color.brandPrimary.opacity(0.15) : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(isSelected ? DesignTokens.Color.brandPrimary : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("avatarEmojiCell_\(emoji)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
