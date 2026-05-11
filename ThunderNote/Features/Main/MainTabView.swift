import SwiftUI

/// 5 tab 主壳：闪记 / 合集 / 联系人 / 收藏 / 我的
/// 顺序与 Android `MainShellFragment` 底部 tab 完全一致。
struct MainTabView: View {
    @EnvironmentObject private var dependencies: AppDependencies

    @State private var selectedTab: MainTab = .flashNote

    var body: some View {
        TabView(selection: $selectedTab) {
            FlashNoteListView(
                viewModel: dependencies.flashNoteListViewModel,
                editViewModelFactory: dependencies.makeFlashNoteEditViewModel,
                chatViewModelFactory: dependencies.makeChatViewModel
            )
            .tabItem {
                Label(MainTab.flashNote.title, systemImage: MainTab.flashNote.iconName)
            }
            .tag(MainTab.flashNote)

            CollectionsTabView()
                .tabItem {
                    Label(MainTab.collections.title, systemImage: MainTab.collections.iconName)
                }
                .tag(MainTab.collections)

            ContactsTabView()
                .tabItem {
                    Label(MainTab.contacts.title, systemImage: MainTab.contacts.iconName)
                }
                .tag(MainTab.contacts)

            FavoritesTabView()
                .tabItem {
                    Label(MainTab.favorites.title, systemImage: MainTab.favorites.iconName)
                }
                .tag(MainTab.favorites)

            ProfileTabView()
                .tabItem {
                    Label(MainTab.profile.title, systemImage: MainTab.profile.iconName)
                }
                .tag(MainTab.profile)
        }
        .tint(DesignTokens.Color.brandPrimary)
        .accessibilityIdentifier("mainTabView")
    }
}

enum MainTab: Hashable, CaseIterable {
    case flashNote, collections, contacts, favorites, profile

    var title: String {
        switch self {
        case .flashNote: return "闪记"
        case .collections: return "合集"
        case .contacts: return "联系人"
        case .favorites: return "收藏"
        case .profile: return "我的"
        }
    }

    var iconName: String {
        switch self {
        case .flashNote: return "bolt.fill"
        case .collections: return "square.grid.2x2.fill"
        case .contacts: return "person.2.fill"
        case .favorites: return "star.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}
