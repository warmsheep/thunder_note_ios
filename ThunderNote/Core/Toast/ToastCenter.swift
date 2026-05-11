import Foundation
import SwiftUI

/// D2-I6-11 Toast 节流 + 网络错误过滤。
///
/// 与 Android `DebugLog.shouldShowToast / isLikelyNetworkIssue` 行为对齐：
/// - 同 `key` 在 `windowMs` 内只弹一次（默认 2s）
/// - 包含网络错误关键字（`network error / timeout / unable to resolve host / ...`）
///   的消息不弹 toast，仅写日志（在 D2-I6-13 DebugLog 接入后写入）
///
/// 设计成 `@MainActor ObservableObject` + 单例：
/// - View 层订阅 `currentToast` 显示 banner
/// - 任意层调 `ToastCenter.shared.show(key:message:)` 触发
@MainActor
public final class ToastCenter: ObservableObject {
    nonisolated(unsafe) public static let shared = ToastCenter()

    public struct Toast: Equatable, Identifiable {
        public let id: UUID
        public let message: String
        public let createdAt: Date

        public init(id: UUID = UUID(), message: String, createdAt: Date = Date()) {
            self.id = id
            self.message = message
            self.createdAt = createdAt
        }
    }

    @Published public private(set) var currentToast: Toast? = nil

    /// 同 key 节流窗口（默认 2s）。
    nonisolated public static let defaultWindow: TimeInterval = 2.0

    private var lastShownAt: [String: Date] = [:]
    private let now: @Sendable () -> Date
    private let logger: (@Sendable (String) -> Void)?

    nonisolated public init(
        now: @Sendable @escaping () -> Date = { Date() },
        logger: (@Sendable (String) -> Void)? = nil
    ) {
        self.now = now
        self.logger = logger
    }

    /// 触发 toast。同 `key` 在 `window` 内会被合并丢弃。
    /// 网络类错误一律不弹，仅记录日志。
    /// - Returns: true 表示真正展示了 toast（用于测试与调用方判断）
    @discardableResult
    public func show(
        key: String,
        message: String,
        window: TimeInterval = ToastCenter.defaultWindow
    ) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if Self.isLikelyNetworkIssue(trimmed) {
            logger?("[toast/dropped/network] \(key): \(trimmed)")
            return false
        }
        if !shouldShow(key: key, window: window) {
            logger?("[toast/dropped/throttled] \(key): \(trimmed)")
            return false
        }
        currentToast = Toast(message: trimmed)
        return true
    }

    /// 视图层在 toast 自然消失后调用，清空 currentToast 让后续同样消息能再次出现。
    public func dismissCurrent() {
        currentToast = nil
    }

    private func shouldShow(key: String, window: TimeInterval) -> Bool {
        guard !key.isEmpty else { return true }
        let nowDate = now()
        if let last = lastShownAt[key], nowDate.timeIntervalSince(last) < window {
            return false
        }
        lastShownAt[key] = nowDate
        return true
    }

    /// 与 Android `DebugLog.isLikelyNetworkIssue` 行为对齐的关键字判定。
    nonisolated public static func isLikelyNetworkIssue(_ message: String) -> Bool {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        let keywords: [String] = [
            "network error",
            "failed to connect",
            "unable to resolve host",
            "timeout",
            "timed out",
            "connection reset",
            "connection refused",
            "software caused connection abort",
            "failed to fetch profile",
            "获取资料失败"
        ]
        return keywords.contains(where: { normalized.contains($0) })
    }
}

/// 视图层 ToastBanner：订阅 `ToastCenter.shared.currentToast`，自动 1.5s 后消失。
public struct ToastBannerView: View {
    @ObservedObject private var center: ToastCenter

    public init(center: ToastCenter = .shared) {
        self.center = center
    }

    public var body: some View {
        VStack {
            if let toast = center.currentToast {
                Text(toast.message)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.78))
                    .clipShape(Capsule())
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        let id = toast.id
                        Task {
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            // 仅在仍是同一条 toast 时才清空，避免覆盖新弹出的。
                            await MainActor.run {
                                if center.currentToast?.id == id {
                                    center.dismissCurrent()
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("toastBanner")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.18), value: center.currentToast)
    }
}
