import Foundation

/// 桥接 `TokenStore` 与 `APIClient.TokenAccessor` 协议；同步 Keychain 读写到异步上下文。
public final class DefaultTokenAccessor: APIClient.TokenAccessor, @unchecked Sendable {
    private let tokenStore: TokenStoring
    private let onSessionUpdated: (@Sendable (LoginResponse) async -> Void)?
    private let onSessionCleared: (@Sendable () async -> Void)?

    public init(
        tokenStore: TokenStoring,
        onSessionUpdated: (@Sendable (LoginResponse) async -> Void)? = nil,
        onSessionCleared: (@Sendable () async -> Void)? = nil
    ) {
        self.tokenStore = tokenStore
        self.onSessionUpdated = onSessionUpdated
        self.onSessionCleared = onSessionCleared
    }

    public func currentAccessToken() async -> String? {
        tokenStore.loadAccessToken()
    }

    public func currentRefreshToken() async -> String? {
        tokenStore.loadRefreshToken()
    }

    public func saveSession(_ response: LoginResponse) async {
        tokenStore.save(loginResponse: response)
        if let onSessionUpdated {
            await onSessionUpdated(response)
        }
    }

    public func clearSession() async {
        tokenStore.clear()
        if let onSessionCleared {
            await onSessionCleared()
        }
    }
}
