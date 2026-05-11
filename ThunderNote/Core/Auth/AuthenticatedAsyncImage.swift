import SwiftUI
import UIKit

/// 带 `Authorization: Bearer <token>` 头的 AsyncImage 等价实现。
/// 与 Web `AuthenticatedAvatar` 思路一致：
/// - 通过 `URLSession.data(for:)` 拉取，请求里挂当前 access token。
/// - 拉取成功后写入内存级 `NSCache`，相同 URL 命中即复用。
/// - SwiftUI 内重绘时不重复发起请求（在 `Task.detached` 内 dedupe）。
///
/// 由于头像 URL 经常是相同的 objectName，命中率高，不再额外做磁盘缓存
/// （媒体下载已经由 `FileRepository.download` 走磁盘缓存；这里只做轻量内存）。
public struct AuthenticatedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let loader: AuthenticatedImageLoader
    @ViewBuilder private let content: (Image) -> Content
    @ViewBuilder private let placeholder: () -> Placeholder

    @State private var uiImage: UIImage? = nil
    @State private var lastURL: URL? = nil

    public init(
        url: URL?,
        loader: AuthenticatedImageLoader,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.loader = loader
        self.content = content
        self.placeholder = placeholder
    }

    public var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            // 切换 URL 时立刻清掉旧图，避免短暂错位
            if lastURL != url {
                uiImage = nil
                lastURL = url
            }
            guard let target = url else { return }
            if let cached = loader.cached(for: target) {
                uiImage = cached
                return
            }
            do {
                let image = try await loader.load(url: target)
                // 异步加载完成时确认 URL 未被换掉，再赋值
                if lastURL == target {
                    uiImage = image
                }
            } catch {
                // 失败保持 placeholder
            }
        }
    }
}

/// 真正负责发请求 + 缓存的 loader；从 `AppDependencies` 注入，便于测试替换。
public final class AuthenticatedImageLoader: @unchecked Sendable {
    public enum LoadError: Error, Equatable {
        case missingURL
        case http(status: Int)
        case decode
        case transport(message: String)
    }

    private let session: URLSession
    private let tokenAccessor: APIClient.TokenAccessor
    private let cache: NSCache<NSURL, UIImage>

    public init(
        session: URLSession,
        tokenAccessor: APIClient.TokenAccessor,
        cacheCountLimit: Int = 100
    ) {
        self.session = session
        self.tokenAccessor = tokenAccessor
        self.cache = NSCache()
        self.cache.countLimit = cacheCountLimit
    }

    public func cached(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    public func load(url: URL) async throws -> UIImage {
        if let cached = cached(for: url) {
            return cached
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = await tokenAccessor.currentAccessToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LoadError.transport(message: error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LoadError.http(status: http.statusCode)
        }
        guard let image = UIImage(data: data) else {
            throw LoadError.decode
        }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// 仅给单测用：手动注入 cache，验证「命中后跳过网络」。
    public func setCached(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}
