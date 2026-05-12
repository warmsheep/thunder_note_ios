import SwiftUI
import Combine

/// D2-I6-17 手势锁前台超时 + 冷启动门禁
@MainActor
public final class GestureLockManager: ObservableObject {
    public static let shared = GestureLockManager()

    @Published public var isLocked: Bool = false
    private var lastBackgroundTime: Date?
    private let timeoutInterval: TimeInterval = 5 * 60 // 5 分钟

    // 用于跳过解锁的标记（D2-I6-18 外部 flow）
    public var bypassUnlockOnce: Bool = false

    private init() {}

    /// App 进入后台时调用
    public func onBackground() {
        // 如果当前已经锁定，不需要更新时间
        if !isLocked {
            lastBackgroundTime = Date()
        }
    }

    /// App 回到前台时调用
    public func onForeground(username: String?, store: GestureLockStoring) {
        if bypassUnlockOnce {
            bypassUnlockOnce = false
            lastBackgroundTime = nil
            return
        }

        guard let username = username, !username.isEmpty else {
            // 未登录
            isLocked = false
            return
        }

        // 没开启手势锁
        if !store.isEnabled(for: username) {
            isLocked = false
            return
        }

        // 判断是否超时，或者是否是冷启动（lastBackgroundTime 为 nil 表示冷启动或者刚才处于解锁状态且没被计时过？
        // 其实冷启动时 `lastBackgroundTime` 是 nil，一定会被锁。
        if let bgTime = lastBackgroundTime {
            if Date().timeIntervalSince(bgTime) >= timeoutInterval {
                isLocked = true
            }
        } else {
            // 冷启动
            isLocked = true
        }

        lastBackgroundTime = nil
    }

    public func unlock() {
        isLocked = false
        lastBackgroundTime = nil
    }
    
    public func lockImmediately() {
        isLocked = true
    }
}
