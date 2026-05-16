import Foundation
import UniformTypeIdentifiers

/// 媒体预览分发类型。与 Android `FilePreviewActivity` / `ImageViewerActivity` /
/// `VideoPlayerActivity` / PDF preview 的分派等价：
/// - `.image`：走自实现 lightbox（双指缩放 + 拖动关闭）
/// - `.video`：`AVPlayerViewController`
/// - `.pdf`：`PDFKit.PDFView`
/// - `.other`：`QLPreviewController` 兜底（含 epub 等所有 QLPreviewController 原生支持的格式）
public enum MediaPreviewKind: Equatable, Sendable {
    case image
    case video
    case pdf
    case textFile
    case other

    public static func resolve(
        mediaType: MessageMediaType,
        fileName: String? = nil,
        contentType: String? = nil
    ) -> MediaPreviewKind {
        switch mediaType {
        case .image: return .image
        case .video: return .video
        case .file, .audio, .text, .composite:
            if let contentType = contentType?.lowercased() {
                if contentType.hasPrefix("image/") { return .image }
                if contentType.hasPrefix("video/") { return .video }
                if contentType == "application/pdf" { return .pdf }
                if contentType.hasPrefix("text/") { return .textFile }
            }
            if let ext = Self.fileExtension(from: fileName)?.lowercased() {
                if ["pdf"].contains(ext) { return .pdf }
                if ["png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff", "tif", "svg"].contains(ext) { return .image }
                if ["mp4", "mov", "m4v", "avi", "webm", "3gp", "mpeg", "mpg", "mkv"].contains(ext) { return .video }
                if Self.isTextFileExtension(ext) { return .textFile }
            }
            return .other
        }
    }

    private static func isTextFileExtension(_ ext: String) -> Bool {
        textFileExtensions.contains(ext)
    }

    private static let textFileExtensions: Set<String> = [
        "txt", "json", "xml", "csv", "log", "md", "html", "htm",
        "java", "py", "js", "ts", "css", "yaml", "yml",
        "sh", "bash", "sql", "rb", "go", "rs",
        "c", "cpp", "h", "m", "swift", "kt",
        "toml", "ini", "cfg", "conf", "properties",
        "pl", "r", "lua", "vim", "dockerfile", "makefile"
    ]

    private static let officeExtensions: Set<String> = [
        "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "rtf", "pages", "numbers", "key"
    ]

    private static func isOfficeExtension(_ ext: String) -> Bool {
        officeExtensions.contains(ext)
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
