import Foundation
import SQLite3

/// D2-I7 sqlite3 轻封装。
///
/// 与 Android Room 的角色对应：单 sqlite 数据库文件 + 顺序化的 schema migration + 简单 statement helper。
/// 设计原则：
/// - 所有访问统一通过这个对象走串行队列；`exec / query / execute(_:bindings:)` 都不会跨线程；
/// - 不提供 ORM 能力：DAO 自己负责 SQL 字符串与参数绑定，避免反射；
/// - migration 表 `tn_schema_version(version INTEGER NOT NULL)` 单行存当前版本号，与
///   Android Room `RoomDatabase.Migration` 概念一致；
/// - 文件路径：`Library/Application Support/tn/tn.sqlite3`，与 `Library/Caches` 分离避免被系统清理。
public final class TNDatabase: @unchecked Sendable {
    public enum DatabaseError: Error, Equatable {
        case openFailed(message: String)
        case prepareFailed(sql: String, message: String)
        case stepFailed(sql: String, message: String)
        case migrationFailed(version: Int, message: String)
    }

    /// 每个 migration 描述：版本号严格递增，从 1 开始；执行后 `PRAGMA user_version` 写入 `version`。
    public struct Migration: Sendable {
        public let version: Int
        public let sql: String
        public init(version: Int, sql: String) {
            self.version = version
            self.sql = sql
        }
    }

    private let queue: DispatchQueue
    private var db: OpaquePointer?
    private let filePath: String

    /// 当前最新 schema 版本。需要新增表 / 字段时往 `Self.migrations` 末尾追加并把这个值 +1。
    public static let latestVersion: Int = 1

    /// 当前注册的 migration 列表（按 version 严格递增）。
    public static let migrations: [Migration] = [
        Migration(version: 1, sql: """
            CREATE TABLE IF NOT EXISTS sync_meta (
                username TEXT NOT NULL PRIMARY KEY,
                last_message_created_at TEXT,
                server_time TEXT,
                updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
            );
        """)
    ]

    public init(fileURL: URL, queueLabel: String = "tn.db.serial") throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.filePath = fileURL.path
        self.queue = DispatchQueue(label: queueLabel)
        try queue.sync {
            try openLocked()
            try runMigrationsLocked(Self.migrations, target: Self.latestVersion)
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Public helpers

    /// 串行队列上执行一段事务，调用方拿到的 `Statement` helper 已经预备好。
    public func write<T>(_ work: (TNDatabaseHandle) throws -> T) throws -> T {
        try queue.sync {
            guard let db else {
                throw DatabaseError.openFailed(message: "db handle nil")
            }
            return try work(TNDatabaseHandle(db: db))
        }
    }

    /// 与 `write` 同语义，只是语义上是只读。当前实现合并在同一串行队列上。
    public func read<T>(_ work: (TNDatabaseHandle) throws -> T) throws -> T {
        try write(work)
    }

    /// 测试 / 登出场景重置整个文件。
    public func deleteFile() throws {
        try queue.sync {
            if let db {
                sqlite3_close(db)
                self.db = nil
            }
            if FileManager.default.fileExists(atPath: filePath) {
                try FileManager.default.removeItem(atPath: filePath)
            }
            try openLocked()
            try runMigrationsLocked(Self.migrations, target: Self.latestVersion)
        }
    }

    // MARK: - Private

    /// 在 `queue.sync` 内调用：直接打开 sqlite handle，不再二次加锁。
    private func openLocked() throws {
        var handle: OpaquePointer? = nil
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(filePath, &handle, flags, nil)
        if result != SQLITE_OK {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle { sqlite3_close(handle) }
            throw DatabaseError.openFailed(message: msg)
        }
        self.db = handle
        // foreign_keys=ON 在多客户端写一致性更稳，但当前没有外键，先打开为后续保留。
        sqlite3_exec(handle, "PRAGMA foreign_keys=ON;", nil, nil, nil)
        sqlite3_exec(handle, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    }

    /// 在 `queue.sync` 内调用：依次执行 pending migrations。
    private func runMigrationsLocked(_ list: [Migration], target: Int) throws {
        guard let db else { throw DatabaseError.openFailed(message: "db handle nil") }
        let current = readUserVersion(db: db)
        guard current < target else { return }
        let pending = list.filter { $0.version > current && $0.version <= target }
            .sorted { $0.version < $1.version }
        for migration in pending {
            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
            if sqlite3_exec(db, migration.sql, nil, nil, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw DatabaseError.migrationFailed(version: migration.version, message: msg)
            }
            let bumpSQL = "PRAGMA user_version=\(migration.version);"
            if sqlite3_exec(db, bumpSQL, nil, nil, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw DatabaseError.migrationFailed(version: migration.version, message: msg)
            }
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        }
    }

    private func readUserVersion(db: OpaquePointer) -> Int {
        var statement: OpaquePointer? = nil
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }
}

/// 串行队列上对 sqlite handle 的轻量操作 API；DAO 通过本对象写 SQL。
public final class TNDatabaseHandle {
    /// SQLite 的 `SQLITE_TRANSIENT` 在 Swift 里没有直接导出，自己拼一个。
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    fileprivate let db: OpaquePointer

    fileprivate init(db: OpaquePointer) {
        self.db = db
    }

    /// 执行无返回值 SQL（DDL / DML / 事务控制）。
    public func exec(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw TNDatabase.DatabaseError.stepFailed(sql: sql, message: msg)
        }
    }

    /// 写入 / 更新 / 删除，带参数绑定。
    public func execute(_ sql: String, bindings: [TNValue] = []) throws {
        var statement: OpaquePointer? = nil
        defer { sqlite3_finalize(statement) }
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw TNDatabase.DatabaseError.prepareFailed(sql: sql, message: String(cString: sqlite3_errmsg(db)))
        }
        try bind(values: bindings, to: statement)
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE || stepResult == SQLITE_ROW else {
            throw TNDatabase.DatabaseError.stepFailed(sql: sql, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    /// 查询多行；`rowMapper` 拿到 `TNRow` 抽取每个 column。
    public func query<T>(_ sql: String, bindings: [TNValue] = [], rowMapper: (TNRow) -> T) throws -> [T] {
        var statement: OpaquePointer? = nil
        defer { sqlite3_finalize(statement) }
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw TNDatabase.DatabaseError.prepareFailed(sql: sql, message: String(cString: sqlite3_errmsg(db)))
        }
        try bind(values: bindings, to: statement)
        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(rowMapper(TNRow(statement: statement!)))
        }
        return rows
    }

    public func queryFirst<T>(_ sql: String, bindings: [TNValue] = [], rowMapper: (TNRow) -> T) throws -> T? {
        try query(sql, bindings: bindings, rowMapper: rowMapper).first
    }

    private func bind(values: [TNValue], to statement: OpaquePointer?) throws {
        for (i, value) in values.enumerated() {
            let index = Int32(i + 1)
            switch value {
            case .null:
                sqlite3_bind_null(statement, index)
            case .int64(let v):
                sqlite3_bind_int64(statement, index, v)
            case .double(let v):
                sqlite3_bind_double(statement, index, v)
            case .text(let v):
                sqlite3_bind_text(statement, index, v, -1, Self.SQLITE_TRANSIENT)
            case .blob(let data):
                _ = data.withUnsafeBytes { raw in
                    sqlite3_bind_blob(statement, index, raw.baseAddress, Int32(data.count), Self.SQLITE_TRANSIENT)
                }
            }
        }
    }
}

/// 行抽取 helper。column index 严格按 SELECT 顺序 0-based。
public struct TNRow {
    private let statement: OpaquePointer

    fileprivate init(statement: OpaquePointer) {
        self.statement = statement
    }

    public func int64(_ column: Int32) -> Int64 {
        sqlite3_column_int64(statement, column)
    }

    public func int(_ column: Int32) -> Int {
        Int(sqlite3_column_int64(statement, column))
    }

    public func text(_ column: Int32) -> String? {
        guard let cstr = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: cstr)
    }

    public func double(_ column: Int32) -> Double {
        sqlite3_column_double(statement, column)
    }

    public func isNull(_ column: Int32) -> Bool {
        sqlite3_column_type(statement, column) == SQLITE_NULL
    }
}

/// 绑定到占位符的值，支持 NULL / Int64 / Double / Text / Blob 五种 sqlite 类型。
public enum TNValue {
    case null
    case int64(Int64)
    case double(Double)
    case text(String)
    case blob(Data)

    public static func int(_ value: Int) -> TNValue { .int64(Int64(value)) }
    public static func optionalText(_ value: String?) -> TNValue {
        if let value { return .text(value) }
        return .null
    }
}
