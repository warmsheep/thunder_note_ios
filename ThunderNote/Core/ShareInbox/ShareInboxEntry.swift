import Foundation

/// 单条 ShareInbox 条目：Share Extension 写入 / 主 App 读取消费。
/// 与 Android `ShareReceiverActivity` 的 intent payload 等价：文本 / 图片 / 视频 / 文件。
public struct ShareInboxEntry: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case text
        case image
        case video
        case file
    }

    public let id: String
    public let kind: Kind
    public let createdAt: String
    /// 文本内容（仅 `kind == .text`）。
    public let text: String?
    /// 相对于 inbox root 的文件路径（仅 image/video/file）。
    public let relativeFilePath: String?
    public let fileName: String?
    public let fileSize: Int64?

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        text: String? = nil,
        relativeFilePath: String? = nil,
        fileName: String? = nil,
        fileSize: Int64? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.text = text
        self.relativeFilePath = relativeFilePath
        self.fileName = fileName
        self.fileSize = fileSize
    }

    public var isText: Bool { kind == .text }

    public func previewLabel() -> String {
        switch kind {
        case .text: return text ?? ""
        case .image: return "[图片] \(fileName ?? "")"
        case .video: return "[视频] \(fileName ?? "")"
        case .file:  return "[文件] \(fileName ?? "")"
        }
    }
}
