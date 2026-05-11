import Foundation

/// D2-I6-01 / D2-I6-02 用户资料仓储。
///
/// 与 Android `UserRepositoryImpl` 行为对齐：
/// - `POST /api/users/profile` 拉取资料
/// - `PUT /api/users/profile` 更新资料
/// - `PUT /api/users/avatar` 更新头像（emoji 字符串或图片 URL）
/// - 资料请求 10s 节流（`PROFILE_REFRESH_COOLDOWN_MS`），重复调用直接复用 in-memory
/// - 本地缓存到 `UserDefaults`（JSON），冷启动直接渲染缓存
public protocol UserRepository: Sendable {
    /// 拉取当前用户资料。`forceRefresh = false` 时若距上次刷新 < 10s 直接返回缓存。
    func fetchProfile(forceRefresh: Bool) async throws -> UserProfile

    /// 更新昵称 / 简介 / preferences。服务端会忽略非可写字段。
    func updateProfile(_ profile: UserProfile) async throws -> UserProfile

    /// 更新头像（emoji 字符串或图片 URL）。
    func updateAvatar(_ avatar: String) async throws

    /// 读取本地缓存的资料（冷启动渲染）。
    func cachedProfile() -> UserProfile?

    /// 清除本地缓存（登出时调）。
    func clearCache()
}

public final class UserRepositoryImpl: UserRepository, @unchecked Sendable {
    /// 资料请求节流窗口。与 Android `PROFILE_REFRESH_COOLDOWN_MS` 一致。
    public static let refreshCooldown: TimeInterval = 10.0

    /// `UserDefaults` 缓存键。注意：iOS 端按 username 隔离，避免多账号串数据。
    public static let cacheKeyPrefix = "tn.user.profile."

    private let apiClient: APIClient
    private let userDefaults: UserDefaults
    private let usernameProvider: @Sendable () -> String?
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var lastRefreshAt: Date? = nil
    private var inflight: Bool = false
    private var cachedSnapshot: UserProfile? = nil

    public init(
        apiClient: APIClient,
        userDefaults: UserDefaults = .standard,
        usernameProvider: @Sendable @escaping () -> String?,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.apiClient = apiClient
        self.userDefaults = userDefaults
        self.usernameProvider = usernameProvider
        self.now = now
        // 启动时尝试加载缓存。
        self.cachedSnapshot = Self.loadCache(userDefaults: userDefaults, username: usernameProvider())
    }

    public func fetchProfile(forceRefresh: Bool) async throws -> UserProfile {
        let snapshot = readSnapshot()
        // 节流命中：仍在 cooldown 窗口内 + 有缓存 + 不强制刷新 → 直接返回缓存。
        if !forceRefresh,
           let last = snapshot.lastRefreshAt,
           let cached = snapshot.cached,
           now().timeIntervalSince(last) < Self.refreshCooldown {
            return cached
        }
        let endpoint = Endpoint<UserProfile>(
            method: .post,
            path: "/api/users/profile",
            body: nil,
            requiresAuth: true
        )
        let profile = try await apiClient.send(endpoint)
        applyAndCache(profile)
        return profile
    }

    public func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        let body = try JSONEncoder.tnDefault.encode(profile)
        let endpoint = Endpoint<UserProfile>(
            method: .put,
            path: "/api/users/profile",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        let updated = try await apiClient.send(endpoint)
        applyAndCache(updated)
        return updated
    }

    public func updateAvatar(_ avatar: String) async throws {
        let body = try JSONEncoder.tnDefault.encode(AvatarUpdateRequest(avatar: avatar))
        let endpoint = Endpoint<String>(
            method: .put,
            path: "/api/users/avatar",
            body: body,
            requiresAuth: true,
            headers: ["Content-Type": "application/json; charset=utf-8"]
        )
        _ = try await apiClient.send(endpoint)
        // 本地立即写入：与 Android 一致，UI 不必等下一次 fetchProfile 才看到新头像。
        var next = readSnapshot().cached ?? UserProfile()
        next.avatar = avatar
        applyAndCache(next)
    }

    public func cachedProfile() -> UserProfile? {
        readSnapshot().cached
    }

    public func clearCache() {
        let username = usernameProvider()
        writeClearState()
        if let username {
            userDefaults.removeObject(forKey: Self.cacheKey(for: username))
        }
    }

    // MARK: - 私有

    /// 读取「最近一次刷新时间 + 缓存」的原子快照。封装 lock/unlock，避免在 async 上下文
    /// 直接调用 `NSLock.unlock()`（Swift 6 严格并发禁用该跨挂起点组合）。
    private func readSnapshot() -> (lastRefreshAt: Date?, cached: UserProfile?) {
        lock.lock()
        defer { lock.unlock() }
        return (lastRefreshAt, cachedSnapshot)
    }

    private func writeClearState() {
        lock.lock()
        defer { lock.unlock() }
        cachedSnapshot = nil
        lastRefreshAt = nil
    }

    private func applyAndCache(_ profile: UserProfile) {
        let username = usernameProvider()
        let ts = now()
        lock.lock()
        cachedSnapshot = profile
        lastRefreshAt = ts
        lock.unlock()
        Self.persistCache(userDefaults: userDefaults, username: username, profile: profile)
    }

    static func cacheKey(for username: String) -> String {
        cacheKeyPrefix + username
    }

    private static func loadCache(userDefaults: UserDefaults, username: String?) -> UserProfile? {
        guard let username, !username.isEmpty else { return nil }
        guard let data = userDefaults.data(forKey: cacheKey(for: username)) else { return nil }
        return try? JSONDecoder.tnDefault.decode(UserProfile.self, from: data)
    }

    private static func persistCache(userDefaults: UserDefaults, username: String?, profile: UserProfile) {
        guard let username, !username.isEmpty else { return }
        guard let data = try? JSONEncoder.tnDefault.encode(profile) else { return }
        userDefaults.set(data, forKey: cacheKey(for: username))
    }
}

