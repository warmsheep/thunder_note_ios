import SwiftUI

struct ContactsTabView: View {
    @EnvironmentObject private var viewModel: ContactsViewModel
    @EnvironmentObject private var dependencies: AppDependencies

    @State private var path: [ChatRoute] = []
    @State private var presentSearch: Bool = false
    @State private var pendingRemoval: ContactUser?
    @State private var pendingPeerWarning: ContactUser?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                segmentedHeader
                content
            }
            .navigationTitle("联系人")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentSearch = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityIdentifier("contactAddButton")
                }
            }
            .refreshable { await viewModel.loadAll() }
            .task { await viewModel.loadAll() }
            .navigationDestination(for: ChatRoute.self) { route in
                ChatView(
                    viewModel: dependencies.makeChatViewModel(
                        key: route.key,
                        title: route.title,
                        targetMessageId: route.targetMessageId
                    ),
                    onAppearAutoUnhide: nil
                )
            }
            .sheet(isPresented: $presentSearch) {
                ContactSearchSheet()
                    .environmentObject(viewModel)
            }
            .alert(
                "确认删除该联系人？",
                isPresented: Binding(
                    get: { pendingRemoval != nil },
                    set: { if !$0 { pendingRemoval = nil } }
                ),
                presenting: pendingRemoval
            ) { contact in
                Button("删除", role: .destructive) {
                    Task {
                        await viewModel.remove(contact)
                        pendingRemoval = nil
                    }
                }
                Button("取消", role: .cancel) { pendingRemoval = nil }
            } message: { contact in
                Text("「\(contact.displayName)」将从联系人列表中移除。")
            }
            .alert(
                "等待对方同意",
                isPresented: Binding(
                    get: { pendingPeerWarning != nil },
                    set: { if !$0 { pendingPeerWarning = nil } }
                ),
                presenting: pendingPeerWarning
            ) { _ in
                Button("好") { pendingPeerWarning = nil }
            } message: { contact in
                Text("「\(contact.displayName)」尚未同意你的好友申请，暂时不能进入聊天。")
            }
            .alert(
                "操作失败",
                isPresented: Binding(
                    get: { viewModel.transientMessage != nil },
                    set: { if !$0 { viewModel.clearTransientMessage() } }
                )
            ) {
                Button("好") { viewModel.clearTransientMessage() }
            } message: {
                Text(viewModel.transientMessage ?? "")
            }
        }
    }

    private var segmentedHeader: some View {
        Picker(
            "",
            selection: Binding(
                get: { viewModel.selectedTab },
                set: { newValue in
                    Task { await viewModel.selectTab(newValue) }
                }
            )
        ) {
            Text("联系人").tag(ContactsViewModel.SegmentTab.contacts)
            HStack(spacing: 4) {
                Text("请求")
                if viewModel.unreadRequestCount > 0 {
                    Text("\(viewModel.unreadRequestCount)")
                        .font(DesignTokens.Typography.caption)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.red)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            .tag(ContactsViewModel.SegmentTab.requests)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .padding(.vertical, DesignTokens.Spacing.small)
        .accessibilityIdentifier("contactsSegmented")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedTab {
        case .contacts:
            contactsList
        case .requests:
            requestsList
        }
    }

    @ViewBuilder
    private var contactsList: some View {
        if viewModel.contacts.isEmpty {
            switch viewModel.contactsLoadState {
            case .idle, .loading:
                loadingView
            case .error(let message):
                errorView(message: message) { Task { await viewModel.loadContacts() } }
            case .loaded:
                emptyContactsView
            }
        } else {
            List {
                if !viewModel.friendContacts.isEmpty {
                    Section("好友") {
                        ForEach(viewModel.friendContacts) { contact in
                            row(for: contact)
                        }
                    }
                }
                if !viewModel.pendingSentContacts.isEmpty {
                    Section("我已发起的申请") {
                        ForEach(viewModel.pendingSentContacts) { contact in
                            row(for: contact)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("contactsList")
        }
    }

    private func row(for contact: ContactUser) -> some View {
        Button {
            if contact.relationStatus == .friend {
                path.append(ChatRoute(
                    key: .peer(contact.userId),
                    title: contact.displayName,
                    flashNoteId: nil
                ))
            } else {
                pendingPeerWarning = contact
            }
        } label: {
            ContactRowView(contact: contact)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingRemoval = contact
            } label: {
                Label("删除", systemImage: "trash")
            }
            .accessibilityIdentifier("contactSwipeDelete-\(contact.userId)")
        }
    }

    @ViewBuilder
    private var requestsList: some View {
        if viewModel.requests.isEmpty {
            switch viewModel.requestsLoadState {
            case .idle, .loading:
                loadingView
            case .error(let message):
                errorView(message: message) { Task { await viewModel.loadRequests() } }
            case .loaded:
                emptyRequestsView
            }
        } else {
            List(viewModel.requests) { request in
                FriendRequestRowView(
                    request: request,
                    onAccept: {
                        Task { await viewModel.accept(request) }
                    },
                    onReject: {
                        Task { await viewModel.reject(request) }
                    }
                )
            }
            .listStyle(.plain)
            .accessibilityIdentifier("friendRequestsList")
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView().tint(DesignTokens.Color.brandPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.Color.danger)
            Text(message)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.textSecondary)
            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.Color.brandPrimary)
        }
        .padding(DesignTokens.Spacing.large)
    }

    private var emptyContactsView: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundStyle(DesignTokens.Color.textSecondary)
            Text("还没有联系人")
                .font(DesignTokens.Typography.title)
            Text("点击右上角加号，搜索并添加好友")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyRequestsView: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(DesignTokens.Color.textSecondary)
            Text("没有待处理的请求")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
