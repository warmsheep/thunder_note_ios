import Foundation

/// 后端通用分页结构（与 Android `PageData<T>` 对齐）。
public struct PageData<T: Decodable & Sendable>: Decodable, Sendable {
    public let records: [T]?
    public let total: Int64?
    public let size: Int64?
    public let current: Int64?
    public let pages: Int64?

    /// 已知字段缺失时给出宽松默认值。
    public var safeRecords: [T] { records ?? [] }
    public var safeCurrent: Int64 { current ?? 0 }
    public var safePages: Int64 { pages ?? 0 }

    public var hasMore: Bool {
        // 后端 `current` / `pages` 一般 1-based；不足一页或拿到最后一页则没有更多。
        guard safePages > 0 else { return false }
        return safeCurrent < safePages
    }
}
