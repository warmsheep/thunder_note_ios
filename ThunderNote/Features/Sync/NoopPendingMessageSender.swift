import Foundation

/// D2-I7-05 / Step 2A 占位 sender。
///
/// Step 2A 只搭起 PendingMessage 表 / DAO / SyncEngine actor / SyncCoordinator 接入；
/// 真正把 `MessageRepository.sendText / sendImage / sendVideo / sendAudio` 与 `FileRepository`
/// 切到走 PendingMessage 队列由 Step 2B 完成。
///
/// 在 Step 2B 落地之前，`SyncEngine.drain()` 真正去派发条目时会调本对象，
/// 这里直接抛错让 SyncEngine 标 `FAILED`，避免假成功删除掉本地 pending 行。
public struct NoopPendingMessageSender: PendingMessageSender {
    public init() {}

    public func send(_ pending: PendingMessageLocal) async throws -> Int64? {
        throw APIError.business(code: -1, message: "PendingMessage 派发链尚未接入（Step 2B）")
    }
}
