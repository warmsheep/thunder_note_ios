import Foundation

/// D2-I7-05 PendingMessage DAO。
///
/// 与 Android `PendingMessageDao` 等价能力：
/// - `insert` 入队（返回新 localId）
/// - `update` 改状态 / attemptCount / errorMessage
/// - `delete(localId:)` 与 `clear(username:)` 单条 / 全清
/// - `pickNextQueued(username:)` 取下一个待派发条目（QUEUED 优先 → FAILED 兜底，按 createdAt 升序）
/// - `findByLocalId` / `listAll(username:)` 用于 SyncEngine 与待同步列表
/// - `countDispatchable(username:)` 给 `SyncCoordinator.pendingCount` 用（不含 SENT / PROCESSING / SENDING 临时态）
///
/// 多账号隔离：所有读写都按 `username` 过滤；登出全清调 `clear(username:)`。
public protocol PendingMessageDao: Sendable {
    @discardableResult
    func insert(_ message: PendingMessageLocal) throws -> Int64
    func update(_ message: PendingMessageLocal) throws
    func delete(localId: Int64) throws
    func clear(username: String) throws
    func findByLocalId(_ localId: Int64) throws -> PendingMessageLocal?
    func listAll(username: String) throws -> [PendingMessageLocal]
    /// 取下一个可派发的条目：优先 `QUEUED`，没有再取 `FAILED`，按 createdAt 升序。
    /// 返回 nil 说明队列空。
    func pickNextDispatchable(username: String) throws -> PendingMessageLocal?
    /// 待同步条目数：QUEUED + UPLOADING + UPLOADED + SENDING + FAILED 都计入，作为 badge 数值。
    /// 与 Android `observeCountByStatuses` 的语义对齐。
    func countDispatchable(username: String) throws -> Int
}

public final class SQLitePendingMessageDao: PendingMessageDao {
    private let database: TNDatabase

    public init(database: TNDatabase) {
        self.database = database
    }

    @discardableResult
    public func insert(_ message: PendingMessageLocal) throws -> Int64 {
        try database.write { handle in
            try handle.execute("""
                INSERT INTO pending_messages (
                    username, conversation_key, flash_note_id, peer_user_id, client_request_id,
                    media_type, content, local_file_path, remote_url, file_name, file_size,
                    media_duration, processed_file_path, thumbnail_url, payload_json, status,
                    created_at, error_message, attempt_count, server_message_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, bindings: [
                .text(message.username),
                .int64(message.conversationKey),
                Self.bindOptInt64(message.flashNoteId),
                Self.bindOptInt64(message.peerUserId),
                .optionalText(message.clientRequestId),
                .optionalText(message.mediaType),
                .optionalText(message.content),
                .optionalText(message.localFilePath),
                .optionalText(message.remoteUrl),
                .optionalText(message.fileName),
                Self.bindOptInt64(message.fileSize),
                Self.bindOptInt64(message.mediaDuration),
                .optionalText(message.processedFilePath),
                .optionalText(message.thumbnailUrl),
                .optionalText(message.payloadJson),
                .text(message.status.rawValue),
                .int64(message.createdAt),
                .optionalText(message.errorMessage),
                .int(message.attemptCount),
                Self.bindOptInt64(message.serverMessageId)
            ])
            return try handle.queryFirst("SELECT last_insert_rowid()") { row in row.int64(0) } ?? 0
        }
    }

    public func update(_ message: PendingMessageLocal) throws {
        try database.write { handle in
            try handle.execute("""
                UPDATE pending_messages SET
                    conversation_key = ?,
                    flash_note_id = ?,
                    peer_user_id = ?,
                    client_request_id = ?,
                    media_type = ?,
                    content = ?,
                    local_file_path = ?,
                    remote_url = ?,
                    file_name = ?,
                    file_size = ?,
                    media_duration = ?,
                    processed_file_path = ?,
                    thumbnail_url = ?,
                    payload_json = ?,
                    status = ?,
                    error_message = ?,
                    attempt_count = ?,
                    server_message_id = ?
                WHERE local_id = ?
            """, bindings: [
                .int64(message.conversationKey),
                Self.bindOptInt64(message.flashNoteId),
                Self.bindOptInt64(message.peerUserId),
                .optionalText(message.clientRequestId),
                .optionalText(message.mediaType),
                .optionalText(message.content),
                .optionalText(message.localFilePath),
                .optionalText(message.remoteUrl),
                .optionalText(message.fileName),
                Self.bindOptInt64(message.fileSize),
                Self.bindOptInt64(message.mediaDuration),
                .optionalText(message.processedFilePath),
                .optionalText(message.thumbnailUrl),
                .optionalText(message.payloadJson),
                .text(message.status.rawValue),
                .optionalText(message.errorMessage),
                .int(message.attemptCount),
                Self.bindOptInt64(message.serverMessageId),
                .int64(message.localId)
            ])
        }
    }

    public func delete(localId: Int64) throws {
        try database.write { handle in
            try handle.execute(
                "DELETE FROM pending_messages WHERE local_id = ?",
                bindings: [.int64(localId)]
            )
        }
    }

    public func clear(username: String) throws {
        try database.write { handle in
            try handle.execute(
                "DELETE FROM pending_messages WHERE username = ?",
                bindings: [.text(username)]
            )
        }
    }

    public func findByLocalId(_ localId: Int64) throws -> PendingMessageLocal? {
        try database.read { handle in
            try handle.queryFirst(
                "SELECT \(PendingMessageLocal.allColumns) FROM pending_messages WHERE local_id = ?",
                bindings: [.int64(localId)],
                rowMapper: Self.rowMapper
            ) ?? nil
        }
    }

    public func listAll(username: String) throws -> [PendingMessageLocal] {
        try database.read { handle in
            try handle.query(
                """
                SELECT \(PendingMessageLocal.allColumns) FROM pending_messages
                WHERE username = ?
                ORDER BY created_at ASC
                """,
                bindings: [.text(username)],
                rowMapper: Self.rowMapper
            )
        }
    }

    public func pickNextDispatchable(username: String) throws -> PendingMessageLocal? {
        try database.read { handle in
            // QUEUED 永远优先；没有 QUEUED 再回到 FAILED。这与 Android `dispatchNext()` 先扫
            // `STATUS_QUEUED`、再扫 `STATUS_FAILED` 的行为对齐。
            let queued = try handle.queryFirst(
                """
                SELECT \(PendingMessageLocal.allColumns) FROM pending_messages
                WHERE username = ? AND status = ?
                ORDER BY created_at ASC LIMIT 1
                """,
                bindings: [.text(username), .text(PendingMessageLocal.Status.queued.rawValue)],
                rowMapper: Self.rowMapper
            )
            if let queued { return queued }
            return try handle.queryFirst(
                """
                SELECT \(PendingMessageLocal.allColumns) FROM pending_messages
                WHERE username = ? AND status = ?
                ORDER BY created_at ASC LIMIT 1
                """,
                bindings: [.text(username), .text(PendingMessageLocal.Status.failed.rawValue)],
                rowMapper: Self.rowMapper
            )
        }
    }

    public func countDispatchable(username: String) throws -> Int {
        try database.read { handle in
            // 待同步含 QUEUED / UPLOADING / UPLOADED / SENDING / FAILED；
            // PROCESSING 是 SyncEngine 自身的瞬态，不计；SENT 入库即删，不会出现。
            try handle.queryFirst(
                """
                SELECT COUNT(*) FROM pending_messages
                WHERE username = ? AND status IN ('QUEUED','UPLOADING','UPLOADED','SENDING','FAILED')
                """,
                bindings: [.text(username)],
                rowMapper: { row in row.int(0) }
            ) ?? 0
        }
    }

    // MARK: - helpers

    private static func bindOptInt64(_ value: Int64?) -> TNValue {
        if let value { return .int64(value) }
        return .null
    }

    private static let rowMapper: (TNRow) -> PendingMessageLocal = { row in
        PendingMessageLocal(
            localId: row.int64(0),
            username: row.text(1) ?? "",
            conversationKey: row.int64(2),
            flashNoteId: row.isNull(3) ? nil : row.int64(3),
            peerUserId: row.isNull(4) ? nil : row.int64(4),
            clientRequestId: row.text(5),
            mediaType: row.text(6),
            content: row.text(7),
            localFilePath: row.text(8),
            remoteUrl: row.text(9),
            fileName: row.text(10),
            fileSize: row.isNull(11) ? nil : row.int64(11),
            mediaDuration: row.isNull(12) ? nil : row.int64(12),
            processedFilePath: row.text(13),
            thumbnailUrl: row.text(14),
            payloadJson: row.text(15),
            status: PendingMessageLocal.Status(rawValue: row.text(16) ?? "")
                ?? .queued,
            createdAt: row.int64(17),
            errorMessage: row.text(18),
            attemptCount: row.int(19),
            serverMessageId: row.isNull(20) ? nil : row.int64(20)
        )
    }
}
