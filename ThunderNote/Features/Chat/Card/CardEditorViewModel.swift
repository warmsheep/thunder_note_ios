import Foundation
import SwiftUI

/// D2-I3-19 卡片编辑器 ViewModel：维护标题 + 至多 9 个媒体 item，
/// 提交时先调 `AttachmentSendingService` 上传到服务器拿 objectName，
/// 再通过 `MessageRepository.createComposite` 落地到目标会话（当前会话 / 收集箱）。
@MainActor
public final class CardEditorViewModel: ObservableObject {
    public static let maxItems = 9
    public static let maxTitleLength = 50

    public enum DraftKind: Equatable {
        case image(localURL: URL)
        case video(localURL: URL)
        case file(localURL: URL, fileName: String, fileSize: Int64)
    }

    public struct Draft: Identifiable, Equatable {
        public let id = UUID()
        public let kind: DraftKind
        public var caption: String? = nil

        public var displayName: String {
            switch kind {
            case .image(let url):     return url.lastPathComponent
            case .video(let url):     return url.lastPathComponent
            case .file(_, let name, _): return name
            }
        }

        public var typeString: String {
            switch kind {
            case .image: return "image"
            case .video: return "video"
            case .file:  return "file"
            }
        }
    }

    public enum Target: Equatable {
        case currentConversation(ConversationKey)
        case inbox  // -> flashNoteId = -1
    }

    @Published public var title: String = ""
    @Published public var drafts: [Draft] = []
    @Published public var target: Target
    @Published public private(set) var isSubmitting: Bool = false
    @Published public var transientMessage: String? = nil

    private let attachmentService: AttachmentSendingService
    private let messageRepository: MessageRepository
    private let session: AuthSession

    public init(
        target: Target,
        attachmentService: AttachmentSendingService,
        messageRepository: MessageRepository,
        session: AuthSession
    ) {
        self.target = target
        self.attachmentService = attachmentService
        self.messageRepository = messageRepository
        self.session = session
    }

    public var canAddMore: Bool { drafts.count < Self.maxItems }
    public var canSubmit: Bool {
        !isSubmitting
            && !drafts.isEmpty
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public var titleCount: Int { title.count }

    public func appendImage(localURL: URL) {
        guard canAddMore else {
            transientMessage = "卡片最多 \(Self.maxItems) 个媒体"
            return
        }
        drafts.append(Draft(kind: .image(localURL: localURL)))
    }

    public func appendVideo(localURL: URL) {
        guard canAddMore else {
            transientMessage = "卡片最多 \(Self.maxItems) 个媒体"
            return
        }
        drafts.append(Draft(kind: .video(localURL: localURL)))
    }

    public func appendFile(localURL: URL) {
        guard canAddMore else {
            transientMessage = "卡片最多 \(Self.maxItems) 个媒体"
            return
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: localURL.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        drafts.append(Draft(kind: .file(
            localURL: localURL,
            fileName: localURL.lastPathComponent,
            fileSize: size
        )))
    }

    public func removeDraft(at index: Int) {
        guard drafts.indices.contains(index) else { return }
        drafts.remove(at: index)
    }

    /// 校验并提交。返回 true 表示成功创建并由调用方关闭编辑器。
    public func submit() async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            transientMessage = "请输入卡片标题"
            return false
        }
        guard trimmed.count <= Self.maxTitleLength else {
            transientMessage = "卡片标题最多 \(Self.maxTitleLength) 字"
            return false
        }
        guard !drafts.isEmpty else {
            transientMessage = "请至少添加一个媒体项"
            return false
        }
        guard drafts.count <= Self.maxItems else {
            transientMessage = "卡片最多 \(Self.maxItems) 个媒体"
            return false
        }
        isSubmitting = true
        defer { isSubmitting = false }

        // 1. 把每个 draft 上传，拿到 objectName。
        var items: [CompositeMessageRequest.Item] = []
        for draft in drafts {
            do {
                let item = try await uploadDraft(draft)
                items.append(item)
            } catch let api as APIError {
                transientMessage = "上传失败：\(api.displayMessage)"
                return false
            } catch {
                transientMessage = "上传失败：\(error.localizedDescription)"
                return false
            }
        }

        // 2. 调 createComposite 创建卡片消息。
        let (flashNoteId, receiverId) = resolveTargetIds()
        let request = CompositeMessageRequest(
            title: trimmed,
            content: nil,
            flashNoteId: flashNoteId,
            receiverId: receiverId,
            items: items
        )
        do {
            _ = try await messageRepository.createComposite(request)
            return true
        } catch let api as APIError {
            transientMessage = api.displayMessage
            return false
        } catch {
            transientMessage = error.localizedDescription
            return false
        }
    }

    public func clearTransientMessage() {
        transientMessage = nil
    }

    // MARK: - 私有

    private func uploadDraft(_ draft: Draft) async throws -> CompositeMessageRequest.Item {
        switch draft.kind {
        case .image(let url):
            let outcome = try await attachmentService.uploadImage(sourceURL: url)
            return CompositeMessageRequest.Item(
                type: "image",
                mediaUrl: outcome.mediaObjectName,
                thumbnailUrl: outcome.thumbnailObjectName,
                fileName: url.lastPathComponent,
                fileSize: nil,
                content: draft.caption
            )
        case .video(let url):
            let outcome = try await attachmentService.uploadVideo(sourceURL: url)
            return CompositeMessageRequest.Item(
                type: "video",
                mediaUrl: outcome.mediaObjectName,
                thumbnailUrl: outcome.thumbnailObjectName,
                fileName: url.lastPathComponent,
                fileSize: nil,
                content: draft.caption
            )
        case .file(let url, let fileName, let fileSize):
            let outcome = try await attachmentService.uploadFile(sourceURL: url)
            return CompositeMessageRequest.Item(
                type: "file",
                mediaUrl: outcome.mediaObjectName,
                thumbnailUrl: nil,
                fileName: fileName,
                fileSize: fileSize > 0 ? fileSize : outcome.fileSize,
                content: draft.caption
            )
        }
    }

    private func resolveTargetIds() -> (Int64?, Int64?) {
        switch target {
        case .currentConversation(let key):
            switch key {
            case .flashNote(let id):
                return (id, nil)
            case .peer(let peerId):
                return (nil, peerId)
            }
        case .inbox:
            return (FlashNote.inboxId, nil)
        }
    }
}
