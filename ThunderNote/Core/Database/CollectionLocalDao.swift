import Foundation

public protocol CollectionLocalDao: Sendable {
    func replaceAll(_ collections: [Collection], username: String) throws
    func listAll(username: String) throws -> [Collection]
    func upsert(_ collection: Collection, username: String) throws
    func delete(username: String, id: Int64) throws
    func clear(username: String) throws
}

public final class SQLiteCollectionLocalDao: CollectionLocalDao {
    private let database: TNDatabase

    public init(database: TNDatabase) {
        self.database = database
    }

    public func replaceAll(_ collections: [Collection], username: String) throws {
        try database.write { handle in
            try handle.execute("BEGIN TRANSACTION")
            do {
                try handle.execute(
                    "DELETE FROM collections_local WHERE username = ?",
                    bindings: [.text(username)]
                )
                for collection in collections {
                    try Self.bindUpsert(handle, collection: collection, username: username)
                }
                try handle.execute("COMMIT")
            } catch {
                try? handle.execute("ROLLBACK")
                throw error
            }
        }
    }

    public func listAll(username: String) throws -> [Collection] {
        try database.read { handle in
            try handle.query(
                """
                SELECT id, user_id, name, description, created_at, updated_at
                FROM collections_local
                WHERE username = ?
                ORDER BY name COLLATE NOCASE ASC, id ASC
                """,
                bindings: [.text(username)],
                rowMapper: Self.rowMapper
            )
        }
    }

    public func upsert(_ collection: Collection, username: String) throws {
        try database.write { handle in
            try Self.bindUpsert(handle, collection: collection, username: username)
        }
    }

    public func delete(username: String, id: Int64) throws {
        try database.write { handle in
            try handle.execute(
                "DELETE FROM collections_local WHERE username = ? AND id = ?",
                bindings: [.text(username), .int64(id)]
            )
        }
    }

    public func clear(username: String) throws {
        try database.write { handle in
            try handle.execute(
                "DELETE FROM collections_local WHERE username = ?",
                bindings: [.text(username)]
            )
        }
    }

    private static func bindUpsert(_ handle: TNDatabaseHandle, collection: Collection, username: String) throws {
        try handle.execute(
            """
            INSERT OR REPLACE INTO collections_local (
                username, id, user_id, name, description, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(username),
                .int64(collection.id),
                collection.userId.map(TNValue.int64) ?? .null,
                .optionalText(collection.name),
                .optionalText(collection.description),
                .optionalText(collection.createdAt),
                .optionalText(collection.updatedAt)
            ]
        )
    }

    private static let rowMapper: (TNRow) -> Collection = { row in
        Collection(
            id: row.int64(0),
            userId: row.isNull(1) ? nil : row.int64(1),
            name: row.text(2),
            description: row.text(3),
            createdAt: row.text(4),
            updatedAt: row.text(5)
        )
    }
}

extension SQLiteCollectionLocalDao: @unchecked Sendable {}
