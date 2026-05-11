import Foundation

/// D2-I7 同步元数据 DAO。
///
/// 表结构（见 `TNDatabase.migrations[v1]`）：
/// - `username` PK：多账号隔离
/// - `last_message_created_at`：服务端 `LocalDateTime` 字符串，用于增量 pull
/// - `server_time`：上次 pull 成功时服务端返回的 `serverTime`
/// - `updated_at`：行更新时间，纯诊断用，未参与逻辑
///
/// 与 Android `SharedPreferences` 里 `tn.sync.last_message_created_at.{username}` 等价。
public protocol SyncMetaDao: Sendable {
    func loadLastMessageCreatedAt(username: String) throws -> String?
    func loadServerTime(username: String) throws -> String?
    func upsert(username: String, lastMessageCreatedAt: String?, serverTime: String?) throws
    func clear(username: String) throws
}

public final class SQLiteSyncMetaDao: SyncMetaDao {
    private let database: TNDatabase

    public init(database: TNDatabase) {
        self.database = database
    }

    public func loadLastMessageCreatedAt(username: String) throws -> String? {
        try database.read { handle in
            try handle.queryFirst(
                "SELECT last_message_created_at FROM sync_meta WHERE username = ?",
                bindings: [.text(username)]
            ) { row in
                row.isNull(0) ? nil : row.text(0)
            } ?? nil
        }
    }

    public func loadServerTime(username: String) throws -> String? {
        try database.read { handle in
            try handle.queryFirst(
                "SELECT server_time FROM sync_meta WHERE username = ?",
                bindings: [.text(username)]
            ) { row in
                row.isNull(0) ? nil : row.text(0)
            } ?? nil
        }
    }

    public func upsert(username: String, lastMessageCreatedAt: String?, serverTime: String?) throws {
        try database.write { handle in
            // UPSERT 写法：sqlite 3.24+ 原生支持 `ON CONFLICT(...) DO UPDATE SET ...`。
            // 注意：避免 server_time / last_message_created_at 单边更新时被覆盖成 null，使用 COALESCE 兜底。
            try handle.execute("""
                INSERT INTO sync_meta (username, last_message_created_at, server_time)
                VALUES (?, ?, ?)
                ON CONFLICT(username) DO UPDATE SET
                    last_message_created_at = COALESCE(excluded.last_message_created_at, sync_meta.last_message_created_at),
                    server_time = COALESCE(excluded.server_time, sync_meta.server_time),
                    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now');
            """, bindings: [
                .text(username),
                .optionalText(lastMessageCreatedAt),
                .optionalText(serverTime)
            ])
        }
    }

    public func clear(username: String) throws {
        try database.write { handle in
            try handle.execute(
                "DELETE FROM sync_meta WHERE username = ?",
                bindings: [.text(username)]
            )
        }
    }
}
