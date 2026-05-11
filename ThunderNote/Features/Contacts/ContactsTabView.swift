import SwiftUI

/// 联系人 tab 占位。详细实现见 D2-I4 阶段。
struct ContactsTabView: View {
    var body: some View {
        TabPlaceholderView(
            icon: "person.2",
            title: MainTab.contacts.title,
            description: "联系人功能将在 D2-I4 阶段接入"
        )
    }
}
