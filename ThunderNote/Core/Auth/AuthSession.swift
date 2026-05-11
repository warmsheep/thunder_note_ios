import Foundation
import Combine

/// 全局认证态。订阅者：
/// - `RootView` 用于决定展示登录页还是主壳
/// - 各 Feature 的 ViewModel 用于在登录态变化时重建依赖
@MainActor
public final class AuthSession: ObservableObject {
    public enum State: Equatable {
        case unknown
        case anonymous
        case authenticated(User)
    }

    @Published public private(set) var state: State = .unknown

    private let tokenStore: TokenStoring
    private let onSignOut: (@Sendable () async -> Void)?

    public init(
        tokenStore: TokenStoring,
        onSignOut: (@Sendable () async -> Void)? = nil
    ) {
        self.tokenStore = tokenStore
        self.onSignOut = onSignOut
    }

    /// 启动时调用一次：根据 Keychain 恢复登录态。
    public func bootstrap() {
        if tokenStore.hasAccessToken,
           let userId = tokenStore.loadUserId(),
           let username = tokenStore.loadUsername() {
            state = .authenticated(User(id: userId, username: username))
        } else {
            state = .anonymous
        }
    }

    public func signIn(_ response: LoginResponse) {
        tokenStore.save(loginResponse: response)
        state = .authenticated(response.user)
    }

    public func signOut() {
        tokenStore.clear()
        state = .anonymous
        if let onSignOut {
            Task.detached { await onSignOut() }
        }
    }

    /// 刷新 token 失败时的强制清退入口。
    public func forceUnauthenticated() {
        tokenStore.clear()
        state = .anonymous
    }

    public var currentUser: User? {
        if case .authenticated(let user) = state { return user }
        return nil
    }
}
