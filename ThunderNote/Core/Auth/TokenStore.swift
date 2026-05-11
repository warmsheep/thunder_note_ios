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

    public init(service: String = "com.flashnote.ios.auth", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - Read

    public func loadAccessToken() -> String? { readString(.accessToken) }
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
        }
    }

    // MARK: - Keychain primitives

    private func readString(_ key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeString(_ key: Key, value: String) {
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
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func delete(_ key: Key) {
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
