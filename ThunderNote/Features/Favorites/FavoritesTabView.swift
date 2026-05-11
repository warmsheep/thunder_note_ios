import SwiftUI

/// 收藏 tab 占位。详细实现见 D2-I5 阶段。
struct FavoritesTabView: View {
    var body: some View {
        TabPlaceholderView(
            icon: "star",
            title: MainTab.favorites.title,
            description: "收藏功能将在 D2-I5 阶段接入"
        )
    }
}
