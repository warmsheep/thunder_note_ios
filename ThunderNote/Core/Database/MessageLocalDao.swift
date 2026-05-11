import Foundation

/// D2-I7-04 服务端确认消息的本地副本 DAO。
///
/// 与 Android `MessageLocalDao` + `MessageLocalEntity` 等价：
/// - 主键 `(username, id)` 保证多账号隔离；
/// - `upsertAll` 走 `INSERT OR REPLACE`，覆盖客户端已有同 id 的版本；
/// - 查询走 `(username, conversation_key)` 索引，按 `created_at` 升序返回，方便 ChatView 直接渲染。
public protocol MessageLocalDao: Sendable {
    func upsert(_ message: Message, username: String, conversationKey: Int64) throws
    func upsertAll(_ items: [(Message, Int64)], username: String) throws
    func listByConversation(username: String, conversationKey: Int64, limit: Int) throws -> [Message]
    func findByClientRequestId(username: String, clientRequestId: String) throws -> Message?
    func deleteByConversation(username: String, conversationKey: Int64) throws
    func deleteAllForUsername(_ username: String) throws
    func deleteByIds(username: String, ids: [Int64]) throws
    func countByConversation(username: String, conversationKey: Int64) throws -> Int
}

public final class SQLiteMessageLocalDao: MessageLocalDao {
    private let database: TNDatabase

    public init(database: TNDatabase) {
        self.database = database
    }

    public func upsert(_ message: Message, username: String, conversationKey: Int64) throws {
        try database.write { handle in
            try Self.bindUpsert(handle, message: message, username: username, conversationKey: conversationKey)
        }
    }

    public func upsertAll(_ items: [(Message, Int64)], username: String) throws {
        guard !items.isEmpty else { return }
        try database.write { handle in
            try handle.execute("BEGIN TRANSACTION")
            do {
                for (message, key) in items {
                    try Self.bindUpsert(handle, message: message, username: username, conversationKey: key)
                }
                try handle.execute("COMMIT")
            } catch {
                try? handle.execute("ROLLBACK")
                throw error
            }
        }
    }

    public func listByConversation(username: String, conversationKey: Int64, limit: Int) throws -> [Message] {
        try database.read { handle in
            try handle.query(
                """
                SELECT id, conversation_key, sender_id, receiver_id, flash_note_id, client_request_id,
                       content, read_status, role, created_at, media_type, media_url, media_duration,
                       thumbnail_url, file_name, file_size, payload_json
                FROM messages_local
                WHERE username = ? AND conversation_key = ?
                ORDER BY datetime(created_at) ASC, id ASC
                LIMIT ?
                """,
                bindings: [.text(username), .int64(conversationKey), .int(limit)],
                rowMapper: Self.rowMapper
            )
        }
    }

    public func findByClientRequestId(username: String, clientRequestId: String) throws -> Message? {
        try database.read { handle in
            try handle.queryFirst(
                """
                SELECT id, conversation_key, sender_id, receiver_id, flash_note_id, client_request_id,
                       content, read_status, role, created_at, media_type, media_url, media_duration,
                       thumbnail_url, file_name, file_size, payload_json
                FROM messages_local
                WHERE username = ? AND client_request_id = ?
                LIMIT 1
                """,
                bindings: [.text(username), .text(clientRequestId)],
                rowMapper: Self.rowMapper
            ) ?? nil
        }
    }

    public func deleteByConversation(username: String, conversationKey: Int64) throws {
        try database.write { handle in
            try handle.execute(
                "DELETE FROM messages_local WHERE username = ? AND conversation_key = ?",
                bindings: [.text(username), .int64(conversationKey)]
            )
        }
    }

    public func deleteByIds(username: String, ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try database.write { handle in
            // 用 `?, ?, ?` 占位符拼出 IN 列表（sqlite 没有数组绑定）。
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            var bindings: [TNValue] = [.text(username)]
            bindings.append(contentsOf: ids.map { .int64($0) })
            try handle.execute(
                "DELETE FROM messages_local WHERE username = ? AND id IN (\(placeholders))",
                bindings: bindings
            )
        }
    }

    public func deleteAllForUsername(_ username: String) throws {
        try database.write { handle in
            try handle.execute(
                "DELETE FROM messages_local WHERE username = ?",
                bindings: [.text(username)]
            )
        }
    }

    public func countByConversation(username: String, conversationKey: Int64) throws -> Int {
        try database.read { handle in
            try handle.queryFirst(
                "SELECT COUNT(*) FROM messages_local WHERE username = ? AND conversation_key = ?",
                bindings: [.text(username), .int64(conversationKey)],
                rowMapper: { row in row.int(0) }
            ) ?? 0
        }
    }

    // MARK: - helpers

    private static func bindOptInt64(_ value: Int64?) -> TNValue {
        if let value { return .int64(value) }
        return .null
    }

    private static func bindOptInt(_ value: Int?) -> TNValue {
        if let value { return .int(value) }
        return .null
    }

    private static func bindUpsert(
        _ handle: TNDatabaseHandle,
        message: Message,
        username: String,
        conversationKey: Int64
    ) throws {
        // 服务端 message 缺 id 的不入库（pending 阶段才会出现）。
        guard let id = message.id else { return }
        let payloadJson: String? = {
            guard let payload = message.payload else { return nil }
            return (try? JSONEncoder.tnDefault.encode(payload)).flatMap { String(data: $0, encoding: .utf8) }
        }()
        try handle.execute("""
            INSERT OR REPLACE INTO messages_local (
                username, id, conversation_key, sender_id, receiver_id, flash_note_id,
                client_request_id, content, read_status, role, created_at, media_type,
                media_url, media_duration, thumbnail_url, file_name, file_size, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, bindings: [
            .text(username),
            .int64(id),
            .int64(conversationKey),
            bindOptInt64(message.senderId),
            bindOptInt64(message.receiverId),
            bindOptInt64(message.flashNoteId),
            .optionalText(message.clientRequestId),
            .optionalText(message.content),
            message.readStatus.map { .int($0 ? 1 : 0) } ?? .null,
            .optionalText(message.role),
            .optionalText(message.createdAt),
            .optionalText(message.mediaType),
            .optionalText(message.mediaUrl),
            bindOptInt(message.mediaDuration),
            .optionalText(message.thumbnailUrl),
            .optionalText(message.fileName),
            bindOptInt64(message.fileSize),
            .optionalText(payloadJson)
        ])
    }

    private static let rowMapper: (TNRow) -> Message = { row in
        let payload: CardPayload? = {
            guard let json = row.text(16), let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(CardPayload.self, from: data)
        }()
        return Message(
            id: row.int64(0),
            senderId: row.isNull(2) ? nil : row.int64(2),
            receiverId: row.isNull(3) ? nil : row.int64(3),
            content: row.text(6),
            readStatus: row.isNull(7) ? nil : row.int(7) != 0,
            flashNoteId: row.isNull(4) ? nil : row.int64(4),
            clientRequestId: row.text(5),
            role: row.text(8),
            createdAt: row.text(9),
            mediaType: row.text(10),
            mediaUrl: row.text(11),
            mediaDuration: row.isNull(12) ? nil : row.int(12),
            thumbnailUrl: row.text(13),
            fileName: row.text(14),
            fileSize: row.isNull(15) ? nil : row.int64(15),
            payload: payload
        )
    }
}

extension SQLiteMessageLocalDao: @unchecked Sendable {}
