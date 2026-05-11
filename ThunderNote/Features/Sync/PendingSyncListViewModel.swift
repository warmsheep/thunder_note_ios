import Foundation

/// D2-I7-09 待同步列表 ViewModel。
///
/// 数据源：`PendingMessageDao.listAll(username:)`。
/// 刷新触发点：
/// - 视图 onAppear
/// - `SyncCoordinator.pendingCount` 变化（由 `SyncEngine.setOnQueueChanged` 在 enqueue/drain 后触发）
///
/// 重试 / 删除通过 `SyncCoordinator.retryPending / deletePending` 走 actor 保证串行。
@MainActor
public final class PendingSyncListViewModel: ObservableObject {
    @Published public private(set) var items: [PendingMessageLocal] = []

    private let dao: PendingMessageDao
    private let usernameProvider: () -> String?

    public init(dao: PendingMessageDao, usernameProvider: @escaping () -> String?) {
        self.dao = dao
        self.usernameProvider = usernameProvider
    }

    /// 同步刷新当前账号的全部 PendingMessage（DAO 内部线程安全，读操作很快）。
    public func refresh() {
        guard let username = usernameProvider(), !username.isEmpty else {
            items = []
            return
        }
        let next = (try? dao.listAll(username: username)) ?? []
        items = next
    }

    /// 按 mediaType / content / fileName 生成行的展示文案，与 Android `PendingSyncAdapter.resolveContentText` 等价。
    public nonisolated static func displayContent(_ item: PendingMessageLocal) -> String {
        if let content = item.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
            return content
        }
        if let fileName = item.fileName?.trimmingCharacters(in: .whitespacesAndNewlines), !fileName.isEmpty {
            return fileName
        }
        let normalized = (item.mediaType ?? "").uppercased()
        switch normalized {
        case "IMAGE": return "[图片]"
        case "VIDEO": return "[视频]"
        case "VOICE": return "[语音]"
        case "FILE": return "[文件]"
        case "TEXT", "": return "[文本]"
        default: return "[媒体]"
        }
    }

    /// 与 Android `resolveTargetText` 等价：私聊 / 收集箱 / 闪记 / 未知。
    public nonisolated static func displayTarget(_ item: PendingMessageLocal) -> String {
        if let peer = item.peerUserId, peer > 0 {
            return "联系人 #\(peer)"
        }
        if let fn = item.flashNoteId {
            if fn == -1 { return "收集箱" }
            if fn > 0 { return "闪记 #\(fn)" }
        }
        return "未知会话"
    }

    /// 状态显示文案；与 Android `resolveStatusLabel` 一致。
    public nonisolated static func displayStatus(_ status: PendingMessageLocal.Status) -> String {
        switch status {
        case .queued: return "排队中"
        case .processing: return "处理中"
        case .uploading: return "上传中"
        case .uploaded: return "已上传"
        case .sending: return "发送中"
        case .sent: return "已发送"
        case .failed: return "失败"
        }
    }

    /// 行级 createdAt 渲染：epoch millis → `yyyy-MM-dd HH:mm`。
    public nonisolated static func displayTime(_ epochMillis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epochMillis) / 1000.0)
        return Self.timeFormatter.string(from: date)
    }

    private nonisolated static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
}
