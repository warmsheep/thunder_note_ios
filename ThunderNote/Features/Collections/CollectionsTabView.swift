import SwiftUI

/// 合集 tab 占位。详细实现见 D2-I4 阶段。
struct CollectionsTabView: View {
    var body: some View {
        TabPlaceholderView(
            icon: "square.grid.2x2",
            title: MainTab.collections.title,
            description: "合集功能将在 D2-I4 阶段接入"
        )
    }
}
