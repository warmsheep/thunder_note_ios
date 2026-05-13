import Foundation
import SwiftUI

/// D2-I6-01 Profile tab 资料 ViewModel。
///
/// 行为与 Android `ProfileTabFragment + UserRepositoryImpl` 主链对齐：
/// - 启动时优先用 `cachedProfile()`（UserDefaults JSON）渲染，避免白屏
/// - 之后异步 `fetchProfile(forceRefresh:false)`，命中 10s cooldown 时直接复用 in-memory
/// - 提供刷新 / 失败 transient toast 通道；登出时清缓存由调用方负责
@MainActor
public final class ProfileViewModel: ObservableObject {
    @Published public private(set) var profile: UserProfile? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public var transientMessage: String? = nil

    private let repository: UserRepository
    private let fileRepository: FileRepository?

    public init(
        repository: UserRepository,
        fileRepository: FileRepository? = nil
    ) {
        self.repository = repository
        self.fileRepository = fileRepository
        // 冷启动直接显示缓存；后续 onAppear 会触发刷新。
        self.profile = repository.cachedProfile()
    }

    public func onAppear() async {
        await load(forceRefresh: false)
    }

    /// 用户主动下拉刷新：跳过 cooldown 强制 refetch。
    public func refresh() async {
        await load(forceRefresh: true)
    }

    public func clearTransientMessage() {
        transientMessage = nil
    }

    /// 接收资料编辑保存的回调，本地直接更新 UI（不重复发请求）。
    public func applyUpdated(_ profile: UserProfile) {
        self.profile = profile
    }

    /// D2-I7：bootstrap / pull 返回 profile 快照后，直接应用到当前 UI 状态。
    /// 这里只做本地状态注入，不额外发起网络请求。
    public func applySyncSnapshot(_ profile: UserProfile) {
        self.profile = profile
    }

    /// D2-I6-04 头像图片裁剪后上传：写临时文件 → `FileRepository.upload` → `updateAvatar(objectName)`。
    /// 失败 transient + 本地 avatar 不变；本地 `Caches/avatar.jpg` 也会被刷新。
    public func updateAvatarFromImageData(_ data: Data) async {
        guard let fileRepository else {
            transientMessage = "未注入文件上传依赖"
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let tmpDir = FileManager.default.temporaryDirectory
        let tmpURL = tmpDir.appendingPathComponent("tn-avatar-\(UUID().uuidString).jpg")
        do {
            try data.write(to: tmpURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tmpURL) }
            let upload = try await fileRepository.upload(
                fileURL: tmpURL,
                mimeType: "image/jpeg",
                progress: nil
            )
            try await repository.updateAvatar(upload.objectName)
            AvatarLocalCache.persist(jpegData: data)
            if let next = repository.cachedProfile() {
                profile = next
            }
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch let fe as FileRepositoryError {
            transientMessage = "头像上传失败：\(fe)"
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    /// D2-I6-03 头像 emoji / 头像 URL 更新。
    /// 调 `PUT /api/users/avatar`，成功后让 repository 把 avatar 写回 in-memory + UserDefaults，
    /// 这里再从 repository 读出最新缓存刷新 UI。
    public func updateAvatar(_ avatar: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await repository.updateAvatar(avatar)
            // repository 已经在内部把 avatar 写入缓存，这里只需要把最新快照拉到 UI。
            if let next = repository.cachedProfile() {
                profile = next
            } else if var current = profile {
                current.avatar = avatar
                profile = current
            }
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    private func load(forceRefresh: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await repository.fetchProfile(forceRefresh: forceRefresh)
            profile = next
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch {
            transientMessage = error.localizedDescription
        }
    }
}
