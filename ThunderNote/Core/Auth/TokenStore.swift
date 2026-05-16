import Foundation
import Security

/// 抽象 Token 存取，方便测试用内存替身。
public protocol TokenStoring: Sendable {
    func loadAccessToken() -> String?
    func loadRefreshToken() -> String?
    func loadUsername() -> String?
    func loadUserId() -> Int64?
    func loadAccessTokenExpiresAt() -> Date?

    func save(loginResponse: LoginResponse)
    func clear()

    var hasAccessToken: Bool { get }
}

/// Keychain 实现：`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`（设备解锁一次即可读取，
/// 但禁止 iCloud 备份同步），与 Android `EncryptedSharedPreferences` 在安全等级上对齐。
public final class KeychainTokenStore: TokenStoring, @unchecked Sendable {
    public enum Key: String, CaseIterable {
        case accessToken = "tn.auth.access_token"
        case refreshToken = "tn.auth.refresh_token"
        case username = "tn.auth.username"
        case userId = "tn.auth.user_id"
        case accessExpiresAt = "tn.auth.access_expires_at"
    }

    private let service: String
    private let accessGroup: String?
    private let lock = NSLock()

    /// 模拟器 / 未签名构建下 Keychain 会返回 `-34018 errSecMissingEntitlement`，
    /// 整个 token 存取链路彻底失效（写入静默失败 → 读取 nil → 401 → 强制登出）。
    /// 检测到该错误后整体切到 `UserDefaults` 兜底；真机带签名走正常 Keychain 路径，
    /// 不会激活兜底，因此不会降低生产安全等级。
    private var useFallback: Bool = false
    private let fallbackDefaults: UserDefaults
    private static let fallbackPrefix = "tn.auth.fallback."

    public init(
        service: String = "com.flashnote.ios.auth",
        accessGroup: String? = nil,
        fallbackDefaults: UserDefaults = .standard
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.fallbackDefaults = fallbackDefaults
        // 进程启动时如果上一次已经走过兜底（UserDefaults 里有任意 token），则继续走兜底；
        // 避免一次会话内 Keychain 正常 / 兜底交替导致读到旧值。
        if fallbackDefaults.string(forKey: Self.fallbackPrefix + Key.accessToken.rawValue) != nil {
            self.useFallback = true
            NSLog("[TN-DIAG] TokenStore: detected prior fallback usage, staying on UserDefaults")
        }
    }

    // MARK: - Read

    public func loadAccessToken() -> String? {
        let t = readString(.accessToken)
        NSLog("[TN-DIAG] loadAccessToken -> \(t == nil ? "nil" : "len=\(t!.count)") fallback=\(useFallback)")
        return t
    }
    public func loadRefreshToken() -> String? { readString(.refreshToken) }
    public func loadUsername() -> String? { readString(.username) }

    public func loadUserId() -> Int64? {
        guard let raw = readString(.userId) else { return nil }
        return Int64(raw)
    }

    public func loadAccessTokenExpiresAt() -> Date? {
        guard let raw = readString(.accessExpiresAt), let secs = Double(raw) else { return nil }
        return Date(timeIntervalSince1970: secs)
    }

    public var hasAccessToken: Bool {
        if let t = loadAccessToken() { return !t.isEmpty }
        return false
    }

    // MARK: - Write

    public func save(loginResponse response: LoginResponse) {
        lock.lock()
        defer { lock.unlock() }
        writeString(.accessToken, value: response.accessToken)
        writeString(.refreshToken, value: response.refreshToken)
        writeString(.username, value: response.user.username)
        writeString(.userId, value: String(response.user.id))
        // 后端返回毫秒
        let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn) / 1000.0)
        writeString(.accessExpiresAt, value: String(expiresAt.timeIntervalSince1970))
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        for key in Key.allCases {
            delete(key)
            fallbackDefaults.removeObject(forKey: Self.fallbackPrefix + key.rawValue)
        }
    }

    // MARK: - Keychain primitives

    private func readString(_ key: Key) -> String? {
        if useFallback {
            return fallbackDefaults.string(forKey: Self.fallbackPrefix + key.rawValue)
        }
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecMissingEntitlement {
            // 模拟器 / 未签名构建：切换到 UserDefaults 兜底。
            NSLog("[TN-DIAG] Keychain SecItemCopyMatching missing-entitlement, switching to UserDefaults fallback")
            useFallback = true
            return fallbackDefaults.string(forKey: Self.fallbackPrefix + key.rawValue)
        }
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeString(_ key: Key, value: String) {
        if useFallback {
            fallbackDefaults.set(value, forKey: Self.fallbackPrefix + key.rawValue)
            return
        }
        let data = Data(value.utf8)
        let query = baseQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecMissingEntitlement {
                NSLog("[TN-DIAG] Keychain SecItemAdd missing-entitlement, switching to UserDefaults fallback")
                useFallback = true
                fallbackDefaults.set(value, forKey: Self.fallbackPrefix + key.rawValue)
            } else if addStatus != errSecSuccess {
                NSLog("[TN-DIAG] Keychain SecItemAdd FAILED key=\(key.rawValue) status=\(addStatus)")
            }
        } else if status == errSecMissingEntitlement {
            NSLog("[TN-DIAG] Keychain SecItemUpdate missing-entitlement, switching to UserDefaults fallback")
            useFallback = true
            fallbackDefaults.set(value, forKey: Self.fallbackPrefix + key.rawValue)
        } else if status != errSecSuccess {
            NSLog("[TN-DIAG] Keychain SecItemUpdate FAILED key=\(key.rawValue) status=\(status)")
        }
    }

    private func delete(_ key: Key) {
        if useFallback {
            fallbackDefaults.removeObject(forKey: Self.fallbackPrefix + key.rawValue)
            return
        }
        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)
    }

    private func baseQuery(for key: Key) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }
}

/// 内存替身，仅用于单元测试；不依赖 Keychain，避免 host App 沙盒受限。
public final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [KeychainTokenStore.Key: String] = [:]

    public init() {}

    public func loadAccessToken() -> String? { read(.accessToken) }
    public func loadRefreshToken() -> String? { read(.refreshToken) }
    public func loadUsername() -> String? { read(.username) }

    public func loadUserId() -> Int64? {
        guard let raw = read(.userId) else { return nil }
        return Int64(raw)
    }

    public func loadAccessTokenExpiresAt() -> Date? {
        guard let raw = read(.accessExpiresAt), let secs = Double(raw) else { return nil }
        return Date(timeIntervalSince1970: secs)
    }

    public var hasAccessToken: Bool {
        if let t = loadAccessToken() { return !t.isEmpty }
        return false
    }

    public func save(loginResponse response: LoginResponse) {
        lock.lock()
        defer { lock.unlock() }
        storage[.accessToken] = response.accessToken
        storage[.refreshToken] = response.refreshToken
        storage[.username] = response.user.username
        storage[.userId] = String(response.user.id)
        let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn) / 1000.0)
        storage[.accessExpiresAt] = String(expiresAt.timeIntervalSince1970)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }

    private func read(_ key: KeychainTokenStore.Key) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }
}
