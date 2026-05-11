import SwiftUI

struct ContactSearchSheet: View {
    @EnvironmentObject private var viewModel: ContactsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var keyword: String = ""
    @State private var results: [ContactSearchUser] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var hasSearched: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                content
            }
            .navigationTitle("添加好友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .background(DesignTokens.Color.background)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignTokens.Color.textSecondary)
            TextField("用户名 / 昵称", text: $keyword)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .onSubmit { triggerSearch() }
                .onChange(of: keyword) { _ in
                    hasSearched = false
                    debounceSearch()
                }
                .accessibilityIdentifier("contactSearchField")
            if !keyword.isEmpty {
                Button {
                    keyword = ""
                    results = []
                    hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DesignTokens.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .padding(.top, DesignTokens.Spacing.small)
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: hasSearched ? "person.crop.circle.badge.questionmark" : "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(DesignTokens.Color.textSecondary)
                Text(hasSearched ? "没有找到匹配的用户" : "输入用户名或昵称开始搜索")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(DesignTokens.Spacing.large)
        } else {
            List(results) { user in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName)
                            .font(DesignTokens.Typography.bodyEmphasized)
                        Text(user.username ?? "")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Color.textSecondary)
                    }
                    Spacer()
                    relationButton(for: user)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func relationButton(for user: ContactSearchUser) -> some View {
        switch user.relationStatus {
        case .friend:
            Text("已是好友")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Color.textSecondary)
        case .pendingSent:
            Text("已申请")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Color.textSecondary)
        case .pendingReceived:
            Text("等待我同意")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Color.textSecondary)
        case .none:
            Button {
                Task {
                    let ok = await viewModel.sendFriendRequest(targetUserId: user.userId)
                    if ok {
                        // 把当前结果中的状态本地更新为 PENDING_SENT
                        if let idx = results.firstIndex(where: { $0.userId == user.userId }) {
                            results[idx] = ContactSearchUser(
                                userId: user.userId,
                                username: user.username,
                                nickname: user.nickname,
                                avatar: user.avatar,
                                relationStatus: .pendingSent
                            )
                        }
                    }
                }
            } label: {
                Text("添加")
                    .font(DesignTokens.Typography.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DesignTokens.Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .accessibilityIdentifier("contactSearchAdd-\(user.userId)")
        }
    }

    private func debounceSearch() {
        searchTask?.cancel()
        let snapshot = keyword
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            if snapshot != keyword { return }
            await runSearch(keyword: snapshot)
        }
    }

    private func triggerSearch() {
        searchTask?.cancel()
        Task { await runSearch(keyword: keyword) }
    }

    private func runSearch(keyword raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            hasSearched = false
            return
        }
        isSearching = true
        let found = await viewModel.search(keyword: trimmed)
        if !Task.isCancelled {
            results = found
            hasSearched = true
        }
        isSearching = false
    }
}
