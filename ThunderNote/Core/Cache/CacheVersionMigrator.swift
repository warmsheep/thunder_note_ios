import Foundation

/// 与 Android `FlashNoteApp.clearStaleCacheOnUpgrade()` 等价。
/// 启动时比对 `currentCacheVersion`，跨过阈值时清理 `Library/Caches` 内容，
/// 避免新版本读取上一个版本格式化方式不同的图片 / 头像 / 临时下载文件。
public final class CacheVersionMigrator: @unchecked Sendable {
    public static let shared = CacheVersionMigrator()

    static let userDefaultsKey = "tn.cache.clear_version"
    /// 升级缓存格式时只需要在这里 +1，下次启动会被自动清理。
    public static let currentCacheVersion = 1

    private let userDefaults: UserDefaults
    private let fileManager: FileManager

    public init(userDefaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
    }

    /// 启动时调用一次。
    public func migrateIfNeeded() {
        let stored = userDefaults.integer(forKey: Self.userDefaultsKey)
        guard stored < Self.currentCacheVersion else { return }
        clearCachesDirectory()
        userDefaults.set(Self.currentCacheVersion, forKey: Self.userDefaultsKey)
    }

    /// 测试或登出时强制清理。
    public func reset() {
        userDefaults.removeObject(forKey: Self.userDefaultsKey)
        clearCachesDirectory()
    }

    /// 暴露给单测 / 工具入口检查当前已记录的版本号。
    public var lastAppliedVersion: Int {
        userDefaults.integer(forKey: Self.userDefaultsKey)
    }

    private func clearCachesDirectory() {
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cachesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for url in contents {
            try? fileManager.removeItem(at: url)
        }
    }
}
