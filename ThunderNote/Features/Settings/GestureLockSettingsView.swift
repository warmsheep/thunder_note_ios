import SwiftUI

/// D2-I6-16 手势锁设置页
@MainActor
public struct GestureLockSettingsView: View {
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.gestureLockStore) private var store
    
    @State private var isEnabled: Bool = false
    @State private var showingSetup = false
    @State private var showingDisableConfirm = false

    public init() {}

    private var username: String {
        if case .authenticated(let user) = session.state {
            return user.username
        }
        return ""
    }

    public var body: some View {
        Form {
            Section {
                Toggle("手势密码", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        if newValue {
                            showingSetup = true
                        } else {
                            showingDisableConfirm = true
                        }
                    }
                ))
            } footer: {
                Text("开启后，下次从后台返回或冷启动时需要绘制手势密码解锁。")
            }
        }
        .navigationTitle("手势密码")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isEnabled = store.isEnabled(for: username)
        }
        .fullScreenCover(isPresented: $showingSetup) {
            GestureLockSetupView(username: username) { success, password in
                showingSetup = false
                if success, let pwd = password {
                    isEnabled = true
                    // D2-I6-19 备份到云端
                    let hash = store.hashPassword(pwd, for: username)
                    Task {
                        try? await dependencies.authRepository.updateGestureLock(passwordHash: hash)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingDisableConfirm) {
            GestureLockVerifyView(username: username, purpose: .disable) { success in
                showingDisableConfirm = false
                if success {
                    store.clear(for: username)
                    isEnabled = false
                    // D2-I6-19 从云端清理
                    Task {
                        try? await dependencies.authRepository.clearGestureLock()
                    }
                }
            }
        }
    }
}

// 供 Environment 使用的 Key
public struct GestureLockStoreKey: EnvironmentKey {
    public static let defaultValue: GestureLockStoring = KeychainGestureLockStore()
}

public extension EnvironmentValues {
    var gestureLockStore: GestureLockStoring {
        get { self[GestureLockStoreKey.self] }
        set { self[GestureLockStoreKey.self] = newValue }
    }
}
