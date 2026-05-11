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
                searchViewModel: dependencies.flashNoteSearchViewModel,
                editViewModelFactory: dependencies.makeFlashNoteEditViewModel,
                chatViewModelFactory: { key, title, targetMessageId in
                    dependencies.makeChatViewModel(
                        key: key,
                        title: title,
                        targetMessageId: targetMessageId
                    )
                }
            )
            .environmentObject(dependencies.contactsViewModel)
            .environmentObject(dependencies.shareInboxConsumer)
            .tabItem {
                Label(MainTab.flashNote.title, systemImage: MainTab.flashNote.iconName)
            }
            .tag(MainTab.flashNote)

            CollectionsTabView()
                .environmentObject(dependencies.collectionsViewModel)
                .environmentObject(dependencies.flashNoteListViewModel)
                .tabItem {
                    Label(MainTab.collections.title, systemImage: MainTab.collections.iconName)
                }
                .tag(MainTab.collections)

            ContactsTabView()
                .environmentObject(dependencies.contactsViewModel)
                .tabItem {
                    Label(MainTab.contacts.title, systemImage: MainTab.contacts.iconName)
                }
                .badge(dependencies.contactsViewModel.contactsTabBadgeCount)
                .tag(MainTab.contacts)

            FavoritesTabView()
                .environmentObject(dependencies.favoritesViewModel)
                .environmentObject(dependencies.flashNoteListViewModel)
                .tabItem {
                    Label(MainTab.favorites.title, systemImage: MainTab.favorites.iconName)
                }
                .tag(MainTab.favorites)

            ProfileTabView(viewModel: dependencies.profileViewModel)
                .tabItem {
                    Label(MainTab.profile.title, systemImage: MainTab.profile.iconName)
                }
                .tag(MainTab.profile)
        }
        .tint(DesignTokens.Color.brandPrimary)
        .accessibilityIdentifier("mainTabView")
        .task {
            // 启动时拉取一次未读请求计数，驱动 contact tab badge。
            await dependencies.contactsViewModel.refreshUnreadCount()
            // 预加载联系人，方便 ShareInbox target picker 立即可用。
            if dependencies.contactsViewModel.contacts.isEmpty {
                await dependencies.contactsViewModel.loadContacts()
            }
        }
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
