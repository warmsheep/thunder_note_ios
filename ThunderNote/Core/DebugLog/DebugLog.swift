import Foundation
import Combine

/// D2-I6-13 调试日志（Ring Buffer + 双文件轮换）
///
/// 功能：
/// 1. 内存中维护最大 200 条的最新日志（Ring Buffer）。
/// 2. 持久化：写入 `Library/Caches/debug_log.txt`。
/// 3. 冷启动轮换：把现有的 `debug_log.txt` 移到 `debug_log_previous.txt`，原 previous 丢弃。
/// 4. 支持按 Level 输出，包含时间戳。
@MainActor
public final class DebugLog: ObservableObject {
    public static let shared = DebugLog()

    public enum Level: String {
        case info = "I"
        case warn = "W"
        case error = "E"
        case crash = "F" // Fatal
    }

    private let maxLines = 200
    private var lines: [String] = []

    @Published public private(set) var currentLogText: String = ""
    public private(set) var previousLogText: String = ""

    private let fileManager = FileManager.default
    private let cacheURL: URL
    private let currentLogURL: URL
    private let previousLogURL: URL
    private var fileHandle: FileHandle?
    private let dateFormatter: DateFormatter

    private init() {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheURL = urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        currentLogURL = cacheURL.appendingPathComponent("debug_log.txt")
        previousLogURL = cacheURL.appendingPathComponent("debug_log_previous.txt")

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        rotateAndInitialize()
    }

    deinit {
        try? fileHandle?.close()
    }

    private func rotateAndInitialize() {
        // 读取 previous（如果有的话，方便在视图里展示）
        // 但在这个阶段，我们要先执行轮换：current -> previous
        if fileManager.fileExists(atPath: previousLogURL.path) {
            try? fileManager.removeItem(at: previousLogURL)
        }
        if fileManager.fileExists(atPath: currentLogURL.path) {
            try? fileManager.moveItem(at: currentLogURL, to: previousLogURL)
        }

        // 把之前的读入内存
        if let previousData = try? Data(contentsOf: previousLogURL),
           let previousString = String(data: previousData, encoding: .utf8) {
            previousLogText = previousString
        }

        // 创建新的 current file
        fileManager.createFile(atPath: currentLogURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: currentLogURL)
        
        DebugLog.info(tag: "DebugLog", message: "Log system initialized.")
    }

    public static func info(tag: String, message: String) {
        shared.log(level: .info, tag: tag, message: message)
    }

    public static func warn(tag: String, message: String) {
        shared.log(level: .warn, tag: tag, message: message)
    }

    public static func error(tag: String, message: String) {
        shared.log(level: .error, tag: tag, message: message)
    }
    
    public static func fatal(tag: String, message: String) {
        shared.log(level: .crash, tag: tag, message: message)
    }

    private func log(level: Level, tag: String, message: String) {
        let timeString = dateFormatter.string(from: Date())
        let line = "[\(timeString)] [\(level.rawValue)] [\(tag)] \(message)"

        // 控制台镜像输出
        print(line)

        // 内存 Ring Buffer
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        currentLogText = lines.joined(separator: "\n")

        // 异步写文件（避免阻塞主线程）
        let data = (line + "\n").data(using: .utf8)
        if let data = data, let handle = fileHandle {
            DispatchQueue.global(qos: .background).async {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
    }

    /// D2-I6-12 登出时清空当前会话日志
    public func clearCurrentSession() {
        lines.removeAll()
        currentLogText = ""
        try? fileHandle?.close()
        try? fileManager.removeItem(at: currentLogURL)
        fileManager.createFile(atPath: currentLogURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: currentLogURL)
        log(level: .info, tag: "DebugLog", message: "Log system cleared on sign out.")
    }
    
    /// 清除所有日志（用于 UI 手动清理）
    public func clearAll() {
        clearCurrentSession()
        try? fileManager.removeItem(at: previousLogURL)
        previousLogText = ""
    }
    
    /// 提供日志文件的 URL 以便分享
    public func getCurrentLogURL() -> URL { currentLogURL }
    public func getPreviousLogURL() -> URL { previousLogURL }
}
