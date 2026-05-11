import Foundation
import SwiftUI

/// D2-I7-08 手动同步入口的协调对象。
///
/// 当前 Step 1 行为：
/// - 暴露 `state`（idle / syncing / failure）+ `pendingCount`（待同步条目数；Step 1 永远为 0）
/// - `manualSync()` 串行执行 `push(empty) → pull`；`bootstrapIfNeeded()` 给登录后调一次
/// - 失败走 transientMessage，由 UI 接 `ToastCenter`
///
/// Step 2（未来）：`pendingCount` 接 PendingMessage 表；`manualSync` 先消费 PendingQueue 再 pull。
@MainActor
public final class SyncCoordinator: ObservableObject {
    public enum State: Equatable {
        case idle
        case syncing
        case failure(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var pendingCount: Int = 0
    @Published public var transientMessage: String? = nil
    @Published public private(set) var lastServerTime: String? = nil

    private let syncRepository: SyncRepository
    private let onPullSucceeded: @Sendable (SyncPullResponse) async -> Void
    /// 防抖：bootstrap 多次触发只跑一次。
    private var bootstrapTask: Task<Void, Never>? = nil

    public init(
        syncRepository: SyncRepository,
        onPullSucceeded: @escaping @Sendable (SyncPullResponse) async -> Void = { _ in }
    ) {
        self.syncRepository = syncRepository
        self.onPullSucceeded = onPullSucceeded
    }

    /// 登录后调一次：单飞控制，重复调用复用现有 Task。
    public func bootstrapIfNeeded() {
        if let bootstrapTask, !bootstrapTask.isCancelled {
            return
        }
        bootstrapTask = Task { [weak self] in
            await self?.runBootstrap()
        }
    }

    /// D2-I7-08 手动同步：当前先尝试 push 空 payload（push 主要回放本地写入，Step 1 没有 PendingMessage，
    /// 所以 payload 一定是空，仅为了贴近 Android `syncAll` 链路），再走 pull 拿增量数据。
    public func manualSync() async {
        guard state != .syncing else { return }
        state = .syncing
        do {
            _ = try await syncRepository.push(SyncPushRequest())
            let response = try await syncRepository.pull()
            lastServerTime = response.serverTime ?? lastServerTime
            state = .idle
            await onPullSucceeded(response)
        } catch let api as APIError {
            state = .failure(api.displayMessage)
            transientMessage = api.displayMessage
        } catch {
            state = .failure(error.localizedDescription)
            transientMessage = error.localizedDescription
        }
    }

    public func clearTransientMessage() {
        transientMessage = nil
    }

    /// 登出时调，让下一次登录重新触发 bootstrap。
    public func resetForSignOut() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        state = .idle
        pendingCount = 0
        lastServerTime = nil
        transientMessage = nil
    }

    private func runBootstrap() async {
        state = .syncing
        do {
            let response = try await syncRepository.bootstrap()
            lastServerTime = response.serverTime ?? lastServerTime
            state = .idle
            await onPullSucceeded(response)
        } catch let api as APIError {
            state = .failure(api.displayMessage)
            transientMessage = api.displayMessage
        } catch {
            state = .failure(error.localizedDescription)
            transientMessage = error.localizedDescription
        }
    }
}
