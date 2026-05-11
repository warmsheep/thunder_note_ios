import Foundation
import SwiftUI

/// 顶层依赖容器：在 App 启动时构造一次。登录态变化触发 Repository 重建逻辑放在这里。
@MainActor
public final class AppDependencies: ObservableObject {
    public let serverConfigStore: ServerConfigStore
    public let serverConfigObservable: ServerConfigStoreObservable
    public let tokenStore: TokenStoring
    public let session: AuthSession
    public let apiClient: APIClient
    public let authRepository: AuthRepository
    public let authViewModel: AuthViewModel

    public init() {
        let serverConfigStore = ServerConfigStore()
        let tokenStore = KeychainTokenStore()
        let session = AuthSession(tokenStore: tokenStore)
        let urlSession = URLSession(configuration: .default)
        let tokenAccessor = DefaultTokenAccessor(
            tokenStore: tokenStore,
            onSessionUpdated: { [weak session] response in
                guard let session else { return }
                await MainActor.run { session.signIn(response) }
            },
            onSessionCleared: { [weak session] in
                guard let session else { return }
                await MainActor.run { session.forceUnauthenticated() }
            }
        )
        let apiClient = APIClient(
            session: urlSession,
            serverConfigStore: serverConfigStore,
            tokenAccessor: tokenAccessor
        )
        let authRepository = AuthRepositoryImpl(apiClient: apiClient)

        self.serverConfigStore = serverConfigStore
        self.tokenStore = tokenStore
        self.session = session
        self.apiClient = apiClient
        self.authRepository = authRepository
        self.authViewModel = AuthViewModel(authRepository: authRepository, session: session)
        self.serverConfigObservable = ServerConfigStoreObservable(
            store: serverConfigStore,
            onSwitched: { [weak tokenStore, weak session] in
                tokenStore?.clear()
                if let session {
                    await MainActor.run { session.forceUnauthenticated() }
                }
            }
        )
    }

    public func bootstrap() {
        CacheVersionMigrator.shared.migrateIfNeeded()
        if ProcessInfo.processInfo.arguments.contains("-tn.uitests.cleanState") {
            tokenStore.clear()
            serverConfigStore.useOfficial()
        }
        session.bootstrap()
    }
}
