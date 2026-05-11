import Foundation

/// 抽象出当前 BaseURL 提供者，方便测试时直接注入固定值。
public protocol ServerConfigStoreProviding: Sendable {
    var currentBaseURL: URL { get }
    var displayLabel: String { get }
    var isOfficial: Bool { get }
}

/// 与 Android `ServerConfigStore` 行为对齐：单站点冷切换。
/// - 默认走 `Self.officialBaseURL`
/// - 自托管站点：用户在登录页输入 URL，归一化后保存；登录页之外不再展示切换入口
public final class ServerConfigStore: ServerConfigStoreProviding, @unchecked Sendable {
    public enum Mode: String, Sendable {
        case official
        case selfHosted = "self_hosted"
    }

    public enum ConfigError: Error, Equatable {
        case empty
        case invalidScheme
        case missingHost
        case extraPath
        case malformed
    }

    public static let officialBaseURL = URL(string: "https://thunder-note.example.com/")!

    public static let modeKey = "tn.server.mode"
    public static let urlKey = "tn.server.self_hosted_url"

    private let userDefaults: UserDefaults
    private let lock = NSLock()

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var currentMode: Mode {
        lock.lock()
        defer { lock.unlock() }
        if let raw = userDefaults.string(forKey: Self.modeKey), let mode = Mode(rawValue: raw) {
            return mode
        }
        return .official
    }

    public var isOfficial: Bool {
        currentMode == .official
    }

    public var currentBaseURL: URL {
        if currentMode == .selfHosted,
           let saved = userDefaults.string(forKey: Self.urlKey),
           !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: saved) {
            return url
        }
        return Self.officialBaseURL
    }

    public var displayLabel: String {
        switch currentMode {
        case .official:
            return "☁️ 闪记服务器"
        case .selfHosted:
            return "🖥️ 自托管：\(currentBaseURL.absoluteString)"
        }
    }

    public func useOfficial() {
        lock.lock()
        defer { lock.unlock() }
        userDefaults.set(Mode.official.rawValue, forKey: Self.modeKey)
        userDefaults.removeObject(forKey: Self.urlKey)
    }

    /// 切换到自托管站点。`rawURL` 会被归一化（自动补 https://、剥除多余路径）。
    /// - Throws: `ConfigError`
    public func useSelfHosted(rawURL: String) throws {
        let normalized = try Self.normalize(rawURL)
        lock.lock()
        defer { lock.unlock() }
        userDefaults.set(Mode.selfHosted.rawValue, forKey: Self.modeKey)
        userDefaults.set(normalized.absoluteString, forKey: Self.urlKey)
    }

    /// 与 Android `ServerConfigStore.normalizeBaseUrl` 保持等价。
    public static func normalize(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ConfigError.empty }
        let withScheme: String
        if trimmed.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) != nil {
            withScheme = trimmed
        } else {
            withScheme = "https://" + trimmed
        }
        guard let components = URLComponents(string: withScheme) else {
            throw ConfigError.malformed
        }
        let scheme = components.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else {
            throw ConfigError.invalidScheme
        }
        guard let host = components.host, !host.isEmpty else {
            throw ConfigError.missingHost
        }
        let path = components.path
        if !path.isEmpty && path != "/" {
            throw ConfigError.extraPath
        }
        let authority: String
        if let port = components.port {
            authority = "\(host):\(port)"
        } else {
            authority = host
        }
        let normalized = "\(scheme)://\(authority)/"
        guard let url = URL(string: normalized) else { throw ConfigError.malformed }
        return url
    }
}
