import Foundation

/// 媒体预加载 helper：进入会话后把最近 N 条 image / video 消息的缩略图
/// 预取到 `FileRepository.download` 缓存。
///
/// 与 Android `preloadRecentMedia` 等价。`NSCache` 本身由 `AsyncImage`
/// 内部维护；这里做的是触发下载，让缩略图文件命中 `Caches/tn.media/<bucket>/`，
/// 再出现在视图时就是命中缓存，不再需要等网络。
public final class MessageMediaPreloader: Sendable {
    private let fileRepository: FileRepository

    public init(fileRepository: FileRepository) {
        self.fileRepository = fileRepository
    }

    /// `items` 内的最近 `limit` 条图片 / 视频消息，提取 thumbnailUrl / mediaUrl
    /// 做一次 fire-and-forget 预下载。已命中缓存的会在 `FileRepository.download`
    /// 内部直接跳过网络请求。
    public func preload(items: [ChatMessageItem], limit: Int = 5) async {
        let targets = items.reversed().prefix(limit * 2).compactMap(preloadCandidate).prefix(limit)
        await withTaskGroup(of: Void.self) { group in
            for objectName in targets {
                group.addTask { [fileRepository] in
                    _ = try? await fileRepository.download(objectName: objectName)
                }
            }
        }
    }

    private func preloadCandidate(from item: ChatMessageItem) -> String? {
        switch item.message.resolvedMediaType {
        case .image:
            if let thumb = item.message.thumbnailUrl, !thumb.isEmpty { return thumb }
            return item.message.mediaUrl
        case .video:
            return item.message.thumbnailUrl  // 视频只预热缩略图；源视频按需下载
        default:
            return nil
        }
    }
}
