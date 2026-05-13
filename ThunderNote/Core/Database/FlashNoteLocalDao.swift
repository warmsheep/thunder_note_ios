import Foundation

public protocol FlashNoteLocalDao: Sendable {
    func replaceAll(_ notes: [FlashNote], username: String) throws
    func listAll(username: String) throws -> [FlashNote]
    func upsert(_ note: FlashNote, username: String) throws
    func delete(username: String, id: Int64) throws
    func clear(username: String) throws
}

public final class SQLiteFlashNoteLocalDao: FlashNoteLocalDao {
    private let database: TNDatabase

    public init(database: TNDatabase) {
        self.database = database
    }

    public func replaceAll(_ notes: [FlashNote], username: String) throws {
        try database.write { handle in
            try handle.execute("BEGIN TRANSACTION")
            do {
                try handle.execute(
                    "DELETE FROM flash_notes_local WHERE username = ?",
                    bindings: [.text(username)]
                )
                for note in notes {
                    try Self.bindUpsert(handle, note: note, username: username)
                }
                try handle.execute("COMMIT")
            } catch {
                try? handle.execute("ROLLBACK")
                throw error
            }
        }
    }

    public func listAll(username: String) throws -> [FlashNote] {
        try database.read { handle in
            try handle.query(
                """
                SELECT id, user_id, title, icon, content, latest_message, tags, deleted, pinned,
                       hidden, inbox, created_at, updated_at
                FROM flash_notes_local
                WHERE username = ?
                ORDER BY CASE WHEN inbox = 1 OR id = -1 THEN 0 ELSE 1 END ASC,
                         CASE WHEN pinned = 1 THEN 0 ELSE 1 END ASC,
                         datetime(updated_at) DESC,
                         id DESC
                """,
                bindings: [.text(username)],
                rowMapper: Self.rowMapper
            )
        }
    }

    public func upsert(_ note: FlashNote, username: String) throws {
        try database.write { handle in
            try Self.bindUpsert(handle, note: note, username: username)
        }
    }

    public func delete(username: String, id: Int64) throws {
        try database.write { handle in
            try handle.execute(
                "DELETE FROM flash_notes_local WHERE username = ? AND id = ?",
                bindings: [.text(username), .int64(id)]
            )
        }
    }

    public func clear(username: String) throws {
        try database.write { handle in
            try handle.execute(
                "DELETE FROM flash_notes_local WHERE username = ?",
                bindings: [.text(username)]
            )
        }
    }

    private static func bindUpsert(_ handle: TNDatabaseHandle, note: FlashNote, username: String) throws {
        try handle.execute(
            """
            INSERT OR REPLACE INTO flash_notes_local (
                username, id, user_id, title, icon, content, latest_message, tags, deleted,
                pinned, hidden, inbox, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(username),
                .int64(note.id),
                note.userId.map(TNValue.int64) ?? .null,
                .optionalText(note.title),
                .optionalText(note.icon),
                .optionalText(note.content),
                .optionalText(note.latestMessage),
                .optionalText(note.tags),
                note.deleted.map { .int($0 ? 1 : 0) } ?? .null,
                note.pinned.map { .int($0 ? 1 : 0) } ?? .null,
                note.hidden.map { .int($0 ? 1 : 0) } ?? .null,
                note.inbox.map { .int($0 ? 1 : 0) } ?? .null,
                .optionalText(note.createdAt),
                .optionalText(note.updatedAt)
            ]
        )
    }

    private static let rowMapper: (TNRow) -> FlashNote = { row in
        FlashNote(
            id: row.int64(0),
            userId: row.isNull(1) ? nil : row.int64(1),
            title: row.text(2),
            icon: row.text(3),
            content: row.text(4),
            latestMessage: row.text(5),
            tags: row.text(6),
            deleted: row.isNull(7) ? nil : row.int(7) != 0,
            pinned: row.isNull(8) ? nil : row.int(8) != 0,
            hidden: row.isNull(9) ? nil : row.int(9) != 0,
            inbox: row.isNull(10) ? nil : row.int(10) != 0,
            createdAt: row.text(11),
            updatedAt: row.text(12)
        )
    }
}

extension SQLiteFlashNoteLocalDao: @unchecked Sendable {}
