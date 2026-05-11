import Foundation

@MainActor
public final class FlashNoteEditViewModel: ObservableObject {
    public enum Mode: Equatable {
        case create
        case edit(FlashNote)
    }

    @Published public var title: String
    @Published public var icon: String
    @Published public var tags: String

    @Published public private(set) var isWorking: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    public let mode: Mode
    private let repository: FlashNoteRepository

    public init(mode: Mode, repository: FlashNoteRepository) {
        self.mode = mode
        self.repository = repository
        switch mode {
        case .create:
            self.title = ""
            self.icon = FlashNoteIcons.defaultIcon
            self.tags = ""
        case .edit(let note):
            self.title = note.title ?? ""
            self.icon = note.icon ?? FlashNoteIcons.defaultIcon
            self.tags = note.tags ?? ""
        }
    }

    public var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    public var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    /// 提交。返回最终 `FlashNote`，由调用方 upsert 到 list 视图模型。
    public func submit() async -> FlashNote? {
        guard !isWorking else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "请输入闪记标题"
            return nil
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        let trimmedTags = tags.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagsValue = trimmedTags.isEmpty ? nil : trimmedTags
        do {
            switch mode {
            case .create:
                return try await repository.create(title: trimmed, icon: icon, tags: tagsValue)
            case .edit(let note):
                return try await repository.update(id: note.id, title: trimmed, icon: icon, tags: tagsValue)
            }
        } catch let api as APIError {
            errorMessage = api.displayMessage
            return nil
        } catch FlashNoteRepositoryError.titleEmpty {
            errorMessage = "请输入闪记标题"
            return nil
        } catch FlashNoteRepositoryError.inboxImmutable {
            errorMessage = "收集箱不允许编辑"
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func clearError() {
        errorMessage = nil
    }
}
