import SwiftUI

/// 设计令牌：颜色 / 间距 / 圆角 / 字体 / 阴影。与 Android `colors.xml` 主色保持等价；
/// 系统语义色直接走 UIKit 适配深色模式，避免重复维护两套色板。
public enum DesignTokens {
    public enum Color {
        /// 主色（橙色系）。与 Android `colors.xml` 中 `brand_primary` 等价。
        public static let brandPrimary = SwiftUI.Color(red: 1.0, green: 0.478, blue: 0.271)
        /// 次主色（暖橙）。
        public static let brandSecondary = SwiftUI.Color(red: 1.0, green: 0.682, blue: 0.310)
        /// 危险色（红）。
        public static let danger = SwiftUI.Color(red: 0.901, green: 0.224, blue: 0.275)

        /// 应用背景；自动适配深色模式。
        public static let background = SwiftUI.Color(.systemBackground)
        /// 卡片 / 容器表面；自动适配深色模式。
        public static let surface = SwiftUI.Color(.secondarySystemBackground)
        /// 主文本色；自动适配深色模式。
        public static let textPrimary = SwiftUI.Color(.label)
        /// 次文本色；自动适配深色模式。
        public static let textSecondary = SwiftUI.Color(.secondaryLabel)
        /// 分割线；自动适配深色模式。
        public static let divider = SwiftUI.Color(.separator)
    }

    public enum Spacing {
        public static let xSmall: CGFloat = 4
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 16
        public static let large: CGFloat = 24
        public static let xLarge: CGFloat = 32
    }

    public enum Radius {
        public static let small: CGFloat = 4
        public static let medium: CGFloat = 8
        public static let large: CGFloat = 12
        public static let pill: CGFloat = 999
    }

    public enum Typography {
        public static let titleLarge = Font.system(size: 28, weight: .bold)
        public static let title = Font.system(size: 22, weight: .semibold)
        public static let body = Font.system(size: 16, weight: .regular)
        public static let bodyEmphasized = Font.system(size: 16, weight: .medium)
        public static let caption = Font.system(size: 13, weight: .regular)
    }

    public enum Shadow {
        public static let smallRadius: CGFloat = 2
        public static let smallY: CGFloat = 1
        public static let smallOpacity: Double = 0.08

        public static let mediumRadius: CGFloat = 8
        public static let mediumY: CGFloat = 4
        public static let mediumOpacity: Double = 0.12
    }
}
