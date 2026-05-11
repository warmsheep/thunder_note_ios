import Foundation

/// 文件上传后端响应（与 Android `FileUploadResult.java` 字段对齐）。
public struct FileUploadResult: Codable, Sendable, Equatable {
    public let objectName: String
    public let originalFilename: String?

    public init(objectName: String, originalFilename: String? = nil) {
        self.objectName = objectName
        self.originalFilename = originalFilename
    }
}
