import SwiftUI

/// 包装 `ServerConfigStore` 为 `ObservableObject`，因为其本身是 thread-safe 的非 ObservableObject。
@MainActor
public final class ServerConfigStoreObservable: ObservableObject {
    @Published public private(set) var displayLabel: String
    @Published public private(set) var isOfficial: Bool
    @Published public private(set) var currentBaseURL: URL
    @Published public private(set) var selfHostedHistory: [URL]

    public let store: ServerConfigStore
    public let onSwitched: (@Sendable () async -> Void)?

    public init(store: ServerConfigStore, onSwitched: (@Sendable () async -> Void)? = nil) {
        self.store = store
        self.onSwitched = onSwitched
        self.displayLabel = store.displayLabel
        self.isOfficial = store.isOfficial
        self.currentBaseURL = store.currentBaseURL
        self.selfHostedHistory = store.selfHostedHistory
    }

    public func useOfficial() {
        store.useOfficial()
        refresh()
        triggerSwitched()
    }

    public func useSelfHosted(rawURL: String) throws {
        try store.useSelfHosted(rawURL: rawURL)
        refresh()
        triggerSwitched()
    }

    public func deleteSelfHostedHistory(url: URL) {
        let previousBaseURL = store.currentBaseURL
        let previousIsOfficial = store.isOfficial
        store.deleteSelfHostedHistory(url: url)
        refresh()
        if previousBaseURL != store.currentBaseURL || previousIsOfficial != store.isOfficial {
            triggerSwitched()
        }
    }

    public func refresh() {
        displayLabel = store.displayLabel
        isOfficial = store.isOfficial
        currentBaseURL = store.currentBaseURL
        selfHostedHistory = store.selfHostedHistory
    }

    private func triggerSwitched() {
        if let onSwitched {
            Task.detached { await onSwitched() }
        }
    }
}

struct ServerConfigSheet: View {
    @EnvironmentObject private var serverConfigStore: ServerConfigStoreObservable
    @Environment(\.dismiss) private var dismiss

    @State private var inputURL: String = ""
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("当前服务器") {
                    Text(serverConfigStore.displayLabel)
                        .accessibilityIdentifier("serverConfigCurrentLabel")
                }

                Section {
                    Button("使用官方服务器") {
                        serverConfigStore.useOfficial()
                        dismiss()
                    }
                    .accessibilityIdentifier("serverConfigUseOfficialButton")
                    .disabled(serverConfigStore.isOfficial)
                } header: {
                    Text("官方服务器")
                } footer: {
                    Text("默认使用闪记官方服务器")
                }

                Section {
                    TextField("https://your-server.com", text: $inputURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .accessibilityIdentifier("serverConfigSelfHostedField")
                    Button("切换到自托管") {
                        do {
                            try serverConfigStore.useSelfHosted(rawURL: inputURL)
                            error = nil
                            dismiss()
                        } catch let configError as ServerConfigStore.ConfigError {
                            error = Self.message(for: configError)
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .accessibilityIdentifier("serverConfigUseSelfHostedButton")
                    if let error {
                        Text(error)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("自托管服务器")
                } footer: {
                    Text("切换会清除当前登录态，需重新登录。HTTPS 必须；HTTP 站点暂不支持运行时启用，需自行打包定制版本。")
                }

                if !serverConfigStore.selfHostedHistory.isEmpty {
                    Section("历史自托管服务器") {
                        ForEach(serverConfigStore.selfHostedHistory, id: \.absoluteString) { url in
                            HStack(spacing: DesignTokens.Spacing.small) {
                                Button {
                                    do {
                                        try serverConfigStore.useSelfHosted(rawURL: url.absoluteString)
                                        error = nil
                                        dismiss()
                                    } catch let configError as ServerConfigStore.ConfigError {
                                        error = Self.message(for: configError)
                                    } catch {
                                        self.error = error.localizedDescription
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(url.host ?? url.absoluteString)
                                            .foregroundStyle(DesignTokens.Color.textPrimary)
                                        Text(url.absoluteString)
                                            .font(DesignTokens.Typography.caption)
                                            .foregroundStyle(DesignTokens.Color.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .accessibilityIdentifier("serverConfigHistorySelectButton")

                                Button(role: .destructive) {
                                    serverConfigStore.deleteSelfHostedHistory(url: url)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityIdentifier("serverConfigHistoryDeleteButton")
                            }
                        }
                    }
                }
            }
            .navigationTitle("切换服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private static func message(for error: ServerConfigStore.ConfigError) -> String {
        switch error {
        case .empty: return "服务器地址不能为空"
        case .invalidScheme: return "仅支持 http 或 https 地址"
        case .missingHost: return "服务器地址缺少主机名"
        case .extraPath: return "服务器地址不能包含额外路径"
        case .malformed: return "服务器地址格式不正确"
        }
    }
}
