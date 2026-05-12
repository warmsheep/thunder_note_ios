import Foundation

/// D2-I6-18 进入外部 flow 跳过解锁
///
/// 当 App 调起 PhotosPicker、相机、分享面板、文件选择等需要跨进程离开当前 App 时，
/// 为了避免这些外部组件返回时触发手势锁，调用 `GestureLockBypass.register()` 打上标记。
/// 与 Android `ExternalFlowGestureUnlockHelper` 等价。
@MainActor
public final class GestureLockBypass {
    public static func register() {
        GestureLockManager.shared.bypassUnlockOnce = true
    }
}
