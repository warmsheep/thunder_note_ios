import Foundation

/// 音频播放互斥协调器：与 Android `AudioPlaybackCoordinator` 等价。
///
/// 任意一个播放器（聊天页 audio bubble 或媒体预览的 AVPlayer 等）开始播放前调
/// `coordinator.play(playerId:)`，coordinator 通过 NotificationCenter 广播
/// 「audio.play」事件，其他正在播放的播放器对比 `playerId` 后自动暂停。
///
/// 这个抽象允许多家播放器共存，而不需要互相直接依赖。
public final class AudioPlaybackCoordinator: @unchecked Sendable {
    public static let shared = AudioPlaybackCoordinator()

    public static let didStartPlayingNotification = Notification.Name("tn.audio.didStartPlaying")
    public static let didStopAllNotification = Notification.Name("tn.audio.didStopAll")
    public static let playerIdKey = "tn.audio.playerId"

    private let lock = NSLock()
    private(set) var currentPlayerId: String?

    public init() {}

    /// 通知 coordinator：playerId 即将开始播放，其他 player 收到广播后应主动 pause。
    public func notifyDidStartPlaying(playerId: String) {
        lock.lock()
        currentPlayerId = playerId
        lock.unlock()
        NotificationCenter.default.post(
            name: Self.didStartPlayingNotification,
            object: nil,
            userInfo: [Self.playerIdKey: playerId]
        )
    }

    /// 通知 coordinator：playerId 已停止 / 暂停。
    public func notifyDidStopPlaying(playerId: String) {
        lock.lock()
        if currentPlayerId == playerId {
            currentPlayerId = nil
        }
        lock.unlock()
    }

    /// App 切到后台时统一暂停所有播放器。
    public func stopAll() {
        lock.lock()
        currentPlayerId = nil
        lock.unlock()
        NotificationCenter.default.post(name: Self.didStopAllNotification, object: nil)
    }
}
