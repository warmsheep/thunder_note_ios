import Foundation

public protocol FavoriteLocalDao: Sendable {
    func replaceAll(_ favorites: [FavoriteItem], username: String) throws
    func listAll(username: String) throws -> [FavoriteItem]
    func upsert(_ favorite: FavoriteItem, username: String) throws
    func delete(username: String, id: Int64) throws
    func deleteByMessageId(username: String, messageId: Int64) throws
    func clear(username: String) throws
}

public final class SQLiteFavoriteLocalDao: FavoriteLocalDao {
    private let database: TNDatabase

    public init(database: TNDatabase) {
        self.database = database
    }

    public func replaceAll(_ favorites: [FavoriteItem], username: String) throws {
        try database.write { handle in
            try handle.execute("BEGIN TRANSACTION")
            do {
                try handle.execute(
                    "DELETE FROM favorites_local WHERE username = ?",
                    bindings: [.text(username)]
                )
                for favorite in favorites {
                    try Self.bindUpsert(handle, favorite: favorite, username: username)
                }
                try handle.execute("COMMIT")
            } catch {
                try? handle.execute("ROLLBACK")
                throw error
            }
        }
    }

    public func listAll(username: String) throws -> [FavoriteItem] {
        try database.read { handle in
            try handle.query(
                """
                SELECT id, message_id, flash_note_id, flash_note_title, flash_note_icon, role,
                       content, media_type, media_url, file_name, file_size, media_duration,
                       favorited_at, message_created_at, payload_json
                FROM favorites_local
                WHERE username = ?
                ORDER BY datetime(favorited_at) DESC, id DESC
                """,
                bindings: [.text(username)],
                rowMapper: Self.rowMapper
            )
        }
    }

    public func upsert(_ favorite: FavoriteItem, username: String) throws {
        try database.write { handle in
            try Self.bindUpsert(handle, favorite: favorite, username: username)
        }
    }

    public func delete(username: String, id: Int64) throws {
        try database.write { handle in
            try handle.execute(
                "DELETE FROM favorites_local WHERE username = ? AND id = ?",
                bindings: [.text(username), .int64(id)]
            )
        }
    }

    public func deleteByMessageId(username: String, messageId: Int64) throws {
        try database.write { handle in
            try handle.execute(
                "DELETE FROM favorites_local WHERE username = ? AND message_id = ?",
                bindings: [.text(username), .int64(messageId)]
            )
        }
    }

    public func clear(username: String) throws {
        try database.write { handle in
            try handle.execute(
                "DELETE FROM favorites_local WHERE username = ?",
                bindings: [.text(username)]
            )
        }
    }

    private static func bindUpsert(_ handle: TNDatabaseHandle, favorite: FavoriteItem, username: String) throws {
        let payloadJson: String? = {
            guard let payload = favorite.payload else { return nil }
            return (try? JSONEncoder.tnDefault.encode(payload)).flatMap { String(data: $0, encoding: .utf8) }
        }()
        try handle.execute(
            """
            INSERT OR REPLACE INTO favorites_local (
                username, id, message_id, flash_note_id, flash_note_title, flash_note_icon,
                role, content, media_type, media_url, file_name, file_size, media_duration,
                favorited_at, message_created_at, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(username),
                .int64(favorite.id),
                favorite.messageId.map(TNValue.int64) ?? .null,
                favorite.flashNoteId.map(TNValue.int64) ?? .null,
                .optionalText(favorite.flashNoteTitle),
                .optionalText(favorite.flashNoteIcon),
                .optionalText(favorite.role),
                .optionalText(favorite.content),
                .optionalText(favorite.mediaType),
                .optionalText(favorite.mediaUrl),
                .optionalText(favorite.fileName),
                favorite.fileSize.map(TNValue.int64) ?? .null,
                favorite.mediaDuration.map(TNValue.int) ?? .null,
                .optionalText(favorite.favoritedAt),
                .optionalText(favorite.messageCreatedAt),
                .optionalText(payloadJson)
            ]
        )
    }

    private static let rowMapper: (TNRow) -> FavoriteItem = { row in
        let payload: CardPayload? = {
            guard let json = row.text(14), let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder.tnDefault.decode(CardPayload.self, from: data)
        }()
        return FavoriteItem(
            id: row.int64(0),
            messageId: row.isNull(1) ? nil : row.int64(1),
            flashNoteId: row.isNull(2) ? nil : row.int64(2),
            flashNoteTitle: row.text(3),
            flashNoteIcon: row.text(4),
            role: row.text(5),
            content: row.text(6),
            mediaType: row.text(7),
            mediaUrl: row.text(8),
            fileName: row.text(9),
            fileSize: row.isNull(10) ? nil : row.int64(10),
            mediaDuration: row.isNull(11) ? nil : row.int(11),
            favoritedAt: row.text(12),
            messageCreatedAt: row.text(13),
            payload: payload
        )
    }
}

extension SQLiteFavoriteLocalDao: @unchecked Sendable {}
