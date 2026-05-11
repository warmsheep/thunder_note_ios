import Foundation

/// 与后端 `Collection` 实体保持字段名一致（与 Android `Collection.java` 对齐）。
/// 后端 MVP 把合集视为「分类目录」；列表视图按 `flash_notes.tags == collection.name`
/// 把闪记归到对应合集。
public struct Collection: Codable, Sendable, Equatable, Identifiable {
    public var id: Int64
    public var userId: Int64?
    public var name: String?
    /// 后端实体仍保留，但 Android 主流程已不再展示「描述」入口；iOS 同样隐藏不展示。
    public var description: String?
    public var createdAt: String?
    public var updatedAt: String?

    public init(
        id: Int64,
        userId: Int64? = nil,
        name: String? = nil,
        description: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return "未命名合集"
    }
}
