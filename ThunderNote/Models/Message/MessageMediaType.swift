import Foundation

/// 与后端 `Message.mediaType` 取值对齐。
/// 当前 MVP 关注 `TEXT`；其他类型会在 D2-I3-08 ~ I3-19 阶段陆续支持。
public enum MessageMediaType: String, Codable, Sendable {
    case text = "TEXT"
    case image = "IMAGE"
    case video = "VIDEO"
    case audio = "AUDIO"
    case file = "FILE"
    case composite = "COMPOSITE"

    public var isMediaAttachment: Bool {
        switch self {
        case .image, .video, .audio, .file: return true
        default: return false
        }
    }

    /// 大小写不敏感解析，兼容后端返回 "image"/"IMAGE"/"file"/"FILE" 等变体。
    /// 同时处理后端用 "voice" 而 iOS 枚举为 `.audio` 的映射。
    public static func resolve(_ raw: String?) -> MessageMediaType {
        guard let raw else { return .text }
        let upper = raw.uppercased()
        switch upper {
        case "TEXT":      return .text
        case "IMAGE":     return .image
        case "VIDEO":     return .video
        case "AUDIO":     return .audio
        case "VOICE":     return .audio
        case "FILE":      return .file
        case "COMPOSITE": return .composite
        case "CARD":      return .composite
        default:          return .text
        }
    }
}
