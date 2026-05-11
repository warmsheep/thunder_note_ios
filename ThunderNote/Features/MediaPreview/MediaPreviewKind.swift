import Foundation
import UniformTypeIdentifiers

/// 媒体预览分发类型。与 Android `FilePreviewActivity` / `ImageViewerActivity` /
/// `VideoPlayerActivity` / PDF preview 的分派等价：
/// - `.image`：走自实现 lightbox（双指缩放 + 拖动关闭）
/// - `.video`：`AVPlayerViewController`
/// - `.pdf`：`PDFKit.PDFView`
/// - `.other`：`QLPreviewController` 兜底
public enum MediaPreviewKind: Equatable, Sendable {
    case image
    case video
    case pdf
    case other

    /// 根据 Message.mediaType / mediaUrl / fileName 启发式判定。
    public static func resolve(
        mediaType: MessageMediaType,
        fileName: String? = nil,
        contentType: String? = nil
    ) -> MediaPreviewKind {
        switch mediaType {
        case .image: return .image
        case .video: return .video
        case .file, .audio, .text, .composite:
            // 优先 content-type 判定，其次扩展名，最后兜底 .other
            if let contentType = contentType?.lowercased() {
                if contentType.hasPrefix("image/") { return .image }
                if contentType.hasPrefix("video/") { return .video }
                if contentType == "application/pdf" { return .pdf }
            }
            if let ext = Self.fileExtension(from: fileName)?.lowercased() {
                if ["pdf"].contains(ext) { return .pdf }
                if ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(ext) { return .image }
                if ["mp4", "mov", "m4v", "avi"].contains(ext) { return .video }
            }
            return .other
        }
    }

    private static func fileExtension(from fileName: String?) -> String? {
        guard let fileName, let dot = fileName.lastIndex(of: ".") else { return nil }
        let afterDot = fileName.index(after: dot)
        guard afterDot < fileName.endIndex else { return nil }
        return String(fileName[afterDot...])
    }
}

/// 一次性生成的预览请求载荷：ObjectName + 展示标题 + 初步类型判定。
public struct MediaPreviewRequest: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: MediaPreviewKind
    public let objectName: String
    public let title: String
    public let fileName: String?

    public init(
        kind: MediaPreviewKind,
        objectName: String,
        title: String,
        fileName: String? = nil
    ) {
        self.kind = kind
        self.objectName = objectName
        self.title = title
        self.fileName = fileName
        self.id = "\(kind)-\(objectName)"
    }
}
