import SwiftUI

/// D2-I2-15 / D2-I2-16 闪记搜索结果面板。
///
/// 与 Android `SearchResultAdapter` 行为对齐：
/// - 顶部分两段「闪记」/「闪记消息」，仅在对应数据非空时显示分组标题。
/// - 闪记段：行点击进入会话（无 targetMessageId）。
/// - 闪记消息段：行展示 `snippet`，行点击进入会话并定位到该 `messageId`
///   （走 D2-I3-05 已实现的 `scrollTargetMessageId + highlightedMessageId`）。
struct FlashNoteSearchPaneView: View {
    @ObservedObject var viewModel: FlashNoteSearchViewModel
    let onPickResult: (FlashNote, Int64?) -> Void

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.hasAnyResult {
                loadingView
            } else if viewModel.isEmptyResult {
                emptyView
            } else if viewModel.hasAnyResult {
                resultList
            } else {
                hintView
            }
        }
        .accessibilityIdentifier("flashNoteSearchPane")
    }

    private var resultList: some View {
        List {
            if !viewModel.noteNameMatched.isEmpty {
                Section {
                    ForEach(viewModel.noteNameMatched, id: \.flashNote.id) { result in
                        Button {
                            onPickResult(result.flashNote, nil)
                        } label: {
                            FlashNoteRowView(note: result.flashNote)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("flashNoteSearchNoteRow-\(result.flashNote.id)")
                    }
                } header: {
                    sectionHeader("闪记")
                }
            }
            if !viewModel.messageContentMatched.isEmpty {
                Section {
                    ForEach(viewModel.messageContentMatched, id: \.flashNote.id) { result in
                        ForEach(result.matchedMessages) { matched in
                            Button {
                                onPickResult(result.flashNote, matched.messageId)
                            } label: {
                                MatchedMessageRow(
                                    note: result.flashNote,
                                    snippet: matched.snippet ?? ""
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(
                                "flashNoteSearchMessageRow-\(result.flashNote.id)-\(matched.messageId)"
                            )
                        }
                    }
                } header: {
                    sectionHeader("闪记消息")
                }
            }
        }
        .listStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DesignTokens.Color.textSecondary)
    }

    private var loadingView: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            ProgressView()
            Text("正在搜索…")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.Color.textSecondary)
            Text("未找到匹配的闪记")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("flashNoteSearchEmpty")
    }

    private var hintView: some View {
        VStack(spacing: DesignTokens.Spacing.medium) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.Color.textSecondary)
            Text("输入关键字搜索闪记标题或消息内容")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignTokens.Spacing.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MatchedMessageRow: View {
    let note: FlashNote
    let snippet: String

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.medium) {
            Text(note.displayIcon)
                .font(.system(size: 26))
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.Color.textPrimary)
                    .lineLimit(1)
                Text(snippet)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignTokens.Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
