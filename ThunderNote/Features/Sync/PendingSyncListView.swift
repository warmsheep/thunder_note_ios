import SwiftUI

/// D2-I7-09 待同步消息列表页。
///
/// 与 Android `PendingSyncListFragment` 等价：展示所有未同步成功的 `PendingMessageLocal`；
/// 顶部「同步」按钮触发 `SyncCoordinator.manualSync()`；行级 swipe 暴露重试 / 删除。
struct PendingSyncListView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var syncCoordinator: SyncCoordinator
    @StateObject private var viewModel: PendingSyncListViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: PendingSyncListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.items.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .navigationTitle("待同步")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await syncCoordinator.manualSync()
                        viewModel.refresh()
                    }
                } label: {
                    if syncCoordinator.state == .syncing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .accessibilityIdentifier("pendingSyncListSyncButton")
                .accessibilityLabel("同步")
                .disabled(syncCoordinator.state == .syncing)
            }
        }
        .onAppear { viewModel.refresh() }
        .onChange(of: syncCoordinator.pendingCount) { _ in
            viewModel.refresh()
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "checkmark.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(DesignTokens.Color.textSecondary)
            Text("暂无待同步消息")
                .font(.system(size: 15))
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Color.background)
        .accessibilityIdentifier("pendingSyncListEmpty")
    }

    private var listContent: some View {
        List {
            Section {
                ForEach(viewModel.items, id: \.localId) { item in
                    row(item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                Task {
                                    await syncCoordinator.deletePending(localId: item.localId)
                                    viewModel.refresh()
                                }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .tint(.red)

                            Button {
                                Task {
                                    await syncCoordinator.retryPending(localId: item.localId)
                                    viewModel.refresh()
                                }
                            } label: {
                                Label("重试", systemImage: "arrow.clockwise")
                            }
                            .tint(.blue)
                        }
                }
            } header: {
                Text("共 \(viewModel.items.count) 条")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.Color.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ item: PendingMessageLocal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(PendingSyncListViewModel.displayContent(item))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DesignTokens.Color.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(PendingSyncListViewModel.displayStatus(item.status))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.status == .failed ? Color.red : Color.orange)
            }
            HStack {
                Text(PendingSyncListViewModel.displayTarget(item))
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Color.textSecondary)
                Spacer()
                Text(PendingSyncListViewModel.displayTime(item.createdAt))
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Color.textSecondary)
            }
            if item.attemptCount > 0 {
                Text("重试次数：\(item.attemptCount)")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Color.textSecondary)
            }
            if let err = item.errorMessage, !err.isEmpty {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
