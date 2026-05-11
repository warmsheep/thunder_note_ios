import Foundation

/// 媒体消息发送统一封装：
/// - 视频：先 `VideoCompressor` 处理 → 上传原文件 + 上传缩略图 → 解析时长。
/// - 图片：渲染本地缩略图 → 上传原图 + 上传缩略图。
/// - 文件：直接上传 + 拿 fileSize / fileName。
///
/// 不依赖 ChatViewModel；返回一份「准备好提交给后端」的 Message payload，由调用方
/// 喂给 `MessageRepository.send`。
public final class AttachmentSendingService: Sendable {
    private let fileRepository: FileRepository

    public init(fileRepository: FileRepository) {
        self.fileRepository = fileRepository
    }

    public struct ImageOutcome: Sendable {
        public let mediaObjectName: String
        public let thumbnailObjectName: String?
    }

    public struct VideoOutcome: Sendable {
        public let mediaObjectName: String
        public let thumbnailObjectName: String?
        public let durationSeconds: Int?
    }

    public struct FileOutcome: Sendable {
        public let mediaObjectName: String
        public let fileName: String
        public let fileSize: Int64
    }

    // MARK: - 图片

    public func uploadImage(
        sourceURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ImageOutcome {
        let mediaUpload = try await fileRepository.upload(
            fileURL: sourceURL,
            mimeType: mimeType(for: sourceURL, defaultType: "image/jpeg"),
            progress: progress
        )
        var thumbnailObject: String?
        if let thumbData = ImageThumbnailRenderer.renderJPEG(from: sourceURL) {
            let thumbURL = try writeTempFile(data: thumbData, ext: "jpg")
            defer { try? FileManager.default.removeItem(at: thumbURL) }
            let thumbUpload = try await fileRepository.upload(
                fileURL: thumbURL,
                mimeType: "image/jpeg",
                progress: nil
            )
            thumbnailObject = thumbUpload.objectName
        }
        return ImageOutcome(
            mediaObjectName: mediaUpload.objectName,
            thumbnailObjectName: thumbnailObject
        )
    }

    // MARK: - 视频

    public func uploadVideo(
        sourceURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> VideoOutcome {
        let processedURL = try await VideoCompressor.compressIfNeeded(at: sourceURL)
        defer {
            if processedURL != sourceURL {
                try? FileManager.default.removeItem(at: processedURL)
            }
        }
        let mediaUpload = try await fileRepository.upload(
            fileURL: processedURL,
            mimeType: mimeType(for: processedURL, defaultType: "video/mp4"),
            progress: progress
        )
        var thumbnailObject: String?
        if let thumb = await MediaMetadata.videoThumbnail(at: sourceURL),
           let jpeg = thumb.jpegData(compressionQuality: 0.78) {
            let thumbURL = try writeTempFile(data: jpeg, ext: "jpg")
            defer { try? FileManager.default.removeItem(at: thumbURL) }
            let thumbUpload = try await fileRepository.upload(
                fileURL: thumbURL,
                mimeType: "image/jpeg",
                progress: nil
            )
            thumbnailObject = thumbUpload.objectName
        }
        let duration = await MediaMetadata.videoDurationSeconds(at: sourceURL)
        return VideoOutcome(
            mediaObjectName: mediaUpload.objectName,
            thumbnailObjectName: thumbnailObject,
            durationSeconds: duration
        )
    }

    // MARK: - 文件

    public func uploadFile(
        sourceURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> FileOutcome {
        let upload = try await fileRepository.upload(
            fileURL: sourceURL,
            mimeType: mimeType(for: sourceURL, defaultType: "application/octet-stream"),
            progress: progress
        )
        let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        return FileOutcome(
            mediaObjectName: upload.objectName,
            fileName: sourceURL.lastPathComponent,
            fileSize: size
        )
    }

    // MARK: - 私有辅助

    private func writeTempFile(data: Data, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tn-attach-\(UUID().uuidString).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func mimeType(for url: URL, defaultType: String) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic": return "image/heic"
        case "gif": return "image/gif"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "pdf": return "application/pdf"
        default: return defaultType
        }
    }
}
