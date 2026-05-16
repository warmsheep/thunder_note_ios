import Foundation
import Security
import CryptoKit

/// D2-I6-16 手势锁存储（按 username 隔离，存 Keychain，存 SHA-256 加盐散列）
public protocol GestureLockStoring: Sendable {
    /// 是否已启用手势锁
    func isEnabled(for username: String) -> Bool
    /// 验证手势密码
    func verify(password: String, for username: String) -> Bool
    /// 设置手势密码
    func set(password: String, for username: String)
    /// 禁用手势锁
    func clear(for username: String)
    /// 获取加密后的 Hash 值用于服务端备份
    func hashPassword(_ password: String, for username: String) -> String
}

public final class KeychainGestureLockStore: GestureLockStoring, @unchecked Sendable {
    private let service: String
    private let lock = NSLock()
    
    // 我们用一个固定的全局 salt，与 Android `GestureLockManager` 等价的本地混淆思路
    private let globalSalt = "tn_gesture_salt_v1_092a3f"

    /// 模拟器 / 未签名构建下 Keychain 会返回 `-34018 errSecMissingEntitlement`，
    /// 写入静默失败 → `isEnabled` 永返 false → 手势锁看似设置成功但下次启动全部失效。
    /// 检测到该错误后整体切到 `UserDefaults` 兜底；真机带签名走正常 Keychain 路径，
    /// 不会激活兜底，因此不会降低生产安全等级。
    private var useFallback: Bool = false
    private let fallbackDefaults: UserDefaults
    private static let fallbackPrefix = "tn.gesture.fallback."
    private static let fallbackEnabledKey = "tn.gesture.fallback.enabled"

    public init(
        service: String = "com.flashnote.ios.gesture",
        fallbackDefaults: UserDefaults = .standard
    ) {
        self.service = service
        self.fallbackDefaults = fallbackDefaults
        // 上一次运行已经走过兜底则继续走兜底，避免一个会话内 Keychain / UserDefaults 交替打架。
        if fallbackDefaults.bool(forKey: Self.fallbackEnabledKey) {
            self.useFallback = true
            NSLog("[TN-DIAG] GestureLockStore: detected prior fallback usage, staying on UserDefaults")
        }
    }

    private func activateFallback() {
        useFallback = true
        fallbackDefaults.set(true, forKey: Self.fallbackEnabledKey)
    }

    private func fallbackKey(for username: String) -> String {
        Self.fallbackPrefix + account(for: username)
    }

    public func isEnabled(for username: String) -> Bool {
        guard !username.isEmpty else { return false }
        return readHash(for: username) != nil
    }

    public func verify(password: String, for username: String) -> Bool {
        guard !username.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        
        guard let savedHash = readHash(for: username) else { return false }
        let currentHash = hash(password: password, username: username)
        return savedHash == currentHash
    }

    public func set(password: String, for username: String) {
        guard !username.isEmpty, !password.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        
        let hashed = hash(password: password, username: username)
        writeHash(hashed, for: username)
    }

    public func clear(for username: String) {
        guard !username.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        
        deleteHash(for: username)
    }

    public func hashPassword(_ password: String, for username: String) -> String {
        return hash(password: password, username: username)
    }

    // MARK: - Hashing

    private func hash(password: String, username: String) -> String {
        // SHA-256(password + globalSalt + username)
        let input = password + globalSalt + username
        let data = Data(input.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Keychain

    private func account(for username: String) -> String {
        "tn.gesture.\(username)"
    }

    private func readHash(for username: String) -> String? {
        if useFallback {
            return fallbackDefaults.string(forKey: fallbackKey(for: username))
        }
        var query = baseQuery(for: username)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecMissingEntitlement {
            NSLog("[TN-DIAG] GestureLockStore SecItemCopyMatching missing-entitlement, switching to UserDefaults fallback")
            activateFallback()
            return fallbackDefaults.string(forKey: fallbackKey(for: username))
        }
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeHash(_ hash: String, for username: String) {
        if useFallback {
            fallbackDefaults.set(hash, forKey: fallbackKey(for: username))
            return
        }
        let data = Data(hash.utf8)
        let query = baseQuery(for: username)
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
                NSLog("[TN-DIAG] GestureLockStore SecItemAdd missing-entitlement, switching to UserDefaults fallback")
                activateFallback()
                fallbackDefaults.set(hash, forKey: fallbackKey(for: username))
            } else if addStatus != errSecSuccess {
                NSLog("[TN-DIAG] GestureLockStore SecItemAdd FAILED user=\(username) status=\(addStatus)")
            }
        } else if status == errSecMissingEntitlement {
            NSLog("[TN-DIAG] GestureLockStore SecItemUpdate missing-entitlement, switching to UserDefaults fallback")
            activateFallback()
            fallbackDefaults.set(hash, forKey: fallbackKey(for: username))
        } else if status != errSecSuccess {
            NSLog("[TN-DIAG] GestureLockStore SecItemUpdate FAILED user=\(username) status=\(status)")
        }
    }

    private func deleteHash(for username: String) {
        // 同时清两侧：避免一侧遮盖另一侧历史数据。
        fallbackDefaults.removeObject(forKey: fallbackKey(for: username))
        if useFallback { return }
        let query = baseQuery(for: username)
        SecItemDelete(query as CFDictionary)
    }

    private func baseQuery(for username: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: username),
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}
