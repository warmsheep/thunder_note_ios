import Foundation

/// Share Extension 与主 App 交换 share payload 的共享存储。
///
/// 真正跨进程要求：
/// - `containerURL` 指向 App Group 容器目录（`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`）。
/// - 当前阶段（未配置 App Group entitlement）退化为主 App / 扩展各自 sandbox 下的
///   `Application Support/tn.share-inbox`，两端不会相互读到；但代码结构与序列化协议
///   已经就绪，后续打开 App Group entitlement 后 **零代码变更** 即可投产。
public final class ShareInboxStore: @unchecked Sendable {
    public static let appGroupIdentifier = "group.com.flashnote.ios"
    public static let inboxDirectoryName = "tn.share-inbox"
    public static let entriesFileName = "entries.json"
    public static let attachmentsDirName = "attachments"

    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    public init?(rootURL: URL? = nil, fileManager: FileManager = .default) {
        if let explicit = rootURL {
            self.rootURL = explicit
        } else if let shared = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
            self.rootURL = shared.appendingPathComponent(Self.inboxDirectoryName, isDirectory: true)
        } else if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            // 无 App Group entitlement 时的 dev fallback（跨进程不通，但主 App 本身
            // 仍可通过本地种子写入测试消费链路）。
            self.rootURL = support.appendingPathComponent(Self.inboxDirectoryName, isDirectory: true)
        } else {
            return nil
        }
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        try? fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        let attachments = self.rootURL.appendingPathComponent(Self.attachmentsDirName, isDirectory: true)
        try? fileManager.createDirectory(at: attachments, withIntermediateDirectories: true)
    }

    public var rootDirectory: URL { rootURL }
    public var entriesFile: URL { rootURL.appendingPathComponent(Self.entriesFileName) }
    public var attachmentsDirectory: URL { rootURL.appendingPathComponent(Self.attachmentsDirName, isDirectory: true) }

    public func allEntries() -> [ShareInboxEntry] {
        lock.lock(); defer { lock.unlock() }
        guard fileManager.fileExists(atPath: entriesFile.path),
              let data = try? Data(contentsOf: entriesFile),
              let decoded = try? decoder.decode([ShareInboxEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    public func append(_ entry: ShareInboxEntry) throws {
        lock.lock(); defer { lock.unlock() }
        var entries = (try? decoder.decode([ShareInboxEntry].self, from: Data(contentsOf: entriesFile))) ?? []
        entries.append(entry)
        let data = try encoder.encode(entries)
        try data.write(to: entriesFile, options: [.atomic])
    }

    public func remove(id: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard fileManager.fileExists(atPath: entriesFile.path) else { return }
        var entries = (try? decoder.decode([ShareInboxEntry].self, from: Data(contentsOf: entriesFile))) ?? []
        entries.removeAll { $0.id == id }
        let data = try encoder.encode(entries)
        try data.write(to: entriesFile, options: [.atomic])
    }

    public func clearAll() throws {
        lock.lock(); defer { lock.unlock() }
        if fileManager.fileExists(atPath: entriesFile.path) {
            try fileManager.removeItem(at: entriesFile)
        }
        if fileManager.fileExists(atPath: attachmentsDirectory.path) {
            try fileManager.removeItem(at: attachmentsDirectory)
            try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        }
    }

    /// 把 Share Extension 里读到的附件（临时 url）保存到共享 attachments 目录，
    /// 返回相对路径（供 `ShareInboxEntry.relativeFilePath` 使用）。
    public func storeAttachment(sourceURL: URL, suggestedName: String?) throws -> String {
        let id = UUID().uuidString
        let cleanName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
        let relative = "\(id)_\(cleanName ?? sourceURL.lastPathComponent)"
        let destination = attachmentsDirectory.appendingPathComponent(relative)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return relative
    }

    /// 把相对路径重新解析为 attachments 目录下的绝对 URL。
    public func resolveAttachmentURL(relativePath: String) -> URL {
        attachmentsDirectory.appendingPathComponent(relativePath)
    }
}
