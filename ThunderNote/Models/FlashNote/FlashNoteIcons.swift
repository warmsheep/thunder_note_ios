import Foundation

/// 与 Android `res/values/arrays.xml` 中 `flashnote_icons` 等价的 emoji 图标集合，顺序保持一致。
public enum FlashNoteIcons {
    public static let all: [String] = [
        "💼", "📚", "❤️", "🍀", "🌟", "🎯",
        "🚀", "🎨", "🎵", "📷", "📝", "💡"
    ]

    /// 创建闪记时的默认图标（与 Android 行为一致：用户未选则给个稳定缺省）。
    public static let defaultIcon: String = "📝"
}
