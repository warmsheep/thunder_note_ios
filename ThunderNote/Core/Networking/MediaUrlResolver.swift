import Foundation

/// 把后端返回的 `objectName`（相对路径）解析为可下载的完整 URL。
/// 与 Android `MediaUrlResolver` 行为对齐：
/// - 已经是绝对 URL → 原样返回
/// - 相对 path → 拼上 baseURL `/api/files/download?objectName=...`
public final class MediaUrlResolver: Sendable {
    private let serverConfigStore: ServerConfigStoreProviding

    public init(serverConfigStore: ServerConfigStoreProviding) {
        self.serverConfigStore = serverConfigStore
    }

    public func resolve(_ objectName: String?) -> URL? {
        guard let objectName, !objectName.isEmpty else { return nil }
        if let direct = URL(string: objectName),
           let scheme = direct.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return direct
        }
        let base = serverConfigStore.currentBaseURL
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let trimmed = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = trimmed + "/api/files/download"
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "objectName", value: objectName))
        components.queryItems = items
        return components.url
    }
}
