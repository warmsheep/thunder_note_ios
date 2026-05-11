import XCTest
@testable import ThunderNote

final class ProfileViewModelTests: XCTestCase {

    /// 冷启动从 repository.cachedProfile() 拿初始值。
    @MainActor
    func test_init_loadsCachedProfile() {
        let repo = StubUserRepository(cached: UserProfile(nickname: "Cold"))
        let vm = ProfileViewModel(repository: repo)
        XCTAssertEqual(vm.profile?.nickname, "Cold")
    }

    /// onAppear 走非强制刷新；命中 cooldown 时仍可加载并设置 profile。
    @MainActor
    func test_onAppear_callsFetchAndSetsProfile() async {
        let repo = StubUserRepository(remote: UserProfile(nickname: "Remote"))
        let vm = ProfileViewModel(repository: repo)
        await vm.onAppear()
        XCTAssertEqual(vm.profile?.nickname, "Remote")
        XCTAssertEqual(repo.fetchCalls.count, 1)
        XCTAssertEqual(repo.fetchCalls.first, false, "onAppear 不强制刷新")
    }

    /// refresh 强制刷新（forceRefresh=true）。
    @MainActor
    func test_refresh_forcesFetch() async {
        let repo = StubUserRepository(remote: UserProfile(nickname: "v1"))
        let vm = ProfileViewModel(repository: repo)
        await vm.refresh()
        XCTAssertEqual(repo.fetchCalls, [true])
    }

    /// 失败 → transientMessage 非空，profile 维持原状。
    @MainActor
    func test_load_failure_setsTransientMessage() async {
        let repo = StubUserRepository(cached: UserProfile(nickname: "Cold"))
        repo.error = APIError.business(code: 50000, message: "服务器错误")
        let vm = ProfileViewModel(repository: repo)
        await vm.onAppear()
        XCTAssertNotNil(vm.transientMessage)
        XCTAssertEqual(vm.profile?.nickname, "Cold")
    }

    /// applyUpdated 由资料编辑回调本地更新，不再发请求。
    @MainActor
    func test_applyUpdated_updatesProfileWithoutFetch() {
        let repo = StubUserRepository(cached: UserProfile(nickname: "Old"))
        let vm = ProfileViewModel(repository: repo)
        vm.applyUpdated(UserProfile(nickname: "New"))
        XCTAssertEqual(vm.profile?.nickname, "New")
        XCTAssertEqual(repo.fetchCalls.count, 0)
    }

    /// D2-I6-03 updateAvatar 成功后 profile.avatar 同步，不发 fetch。
    @MainActor
    func test_updateAvatar_success_updatesAvatarAndKeepsOtherFields() async {
        let repo = StubUserRepository(cached: UserProfile(bio: "Hi", avatar: "💼", nickname: "Old"))
        let vm = ProfileViewModel(repository: repo)
        await vm.updateAvatar("🚀")
        XCTAssertEqual(vm.profile?.avatar, "🚀")
        XCTAssertEqual(vm.profile?.nickname, "Old")
        XCTAssertEqual(vm.profile?.bio, "Hi")
        XCTAssertEqual(repo.fetchCalls.count, 0, "更新头像不应触发 fetch")
        XCTAssertEqual(repo.updateAvatarCalls, ["🚀"])
    }

    /// updateAvatar 失败时设置 transientMessage，profile 不被破坏。
    @MainActor
    func test_updateAvatar_failure_setsTransientMessage() async {
        let repo = StubUserRepository(cached: UserProfile(avatar: "💼", nickname: "Old"))
        repo.updateAvatarError = APIError.business(code: 50000, message: "上传失败")
        let vm = ProfileViewModel(repository: repo)
        await vm.updateAvatar("🚀")
        XCTAssertNotNil(vm.transientMessage)
        XCTAssertEqual(vm.profile?.avatar, "💼", "失败时本地头像不应改动")
    }

    /// D2-I6-04 updateAvatarFromImageData：先调 FileRepository.upload 拿 objectName，
    /// 再调 UserRepository.updateAvatar(objectName)；UI 状态最终 avatar == objectName。
    @MainActor
    func test_updateAvatarFromImageData_uploadsThenUpdatesAvatar() async {
        let repo = StubUserRepository(cached: UserProfile(avatar: "💼", nickname: "Old"))
        let fileRepo = StubFileRepoForAvatar(objectName: "1/avatar-xyz.jpg")
        let vm = ProfileViewModel(repository: repo, fileRepository: fileRepo)
        await vm.updateAvatarFromImageData(Data("jpeg".utf8))
        XCTAssertEqual(fileRepo.uploadCount, 1)
        XCTAssertEqual(repo.updateAvatarCalls, ["1/avatar-xyz.jpg"])
        XCTAssertEqual(vm.profile?.avatar, "1/avatar-xyz.jpg")
        XCTAssertNil(vm.transientMessage)
    }

    /// 上传失败时不应触发 updateAvatar，且 transient 给出错误。
    @MainActor
    func test_updateAvatarFromImageData_uploadFailure_doesNotCallUpdateAvatar() async {
        let repo = StubUserRepository(cached: UserProfile(avatar: "💼", nickname: "Old"))
        let fileRepo = StubFileRepoForAvatar(objectName: "ignored", shouldFail: true)
        let vm = ProfileViewModel(repository: repo, fileRepository: fileRepo)
        await vm.updateAvatarFromImageData(Data("jpeg".utf8))
        XCTAssertEqual(repo.updateAvatarCalls.count, 0)
        XCTAssertEqual(vm.profile?.avatar, "💼", "上传失败时不应改动 avatar")
        XCTAssertNotNil(vm.transientMessage)
    }
}

/// 头像专用的最小 FileRepository stub。
private final class StubFileRepoForAvatar: FileRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.profile.avatar.file")
    private var _uploadCount: Int = 0
    private let objectName: String
    private let shouldFail: Bool

    init(objectName: String, shouldFail: Bool = false) {
        self.objectName = objectName
        self.shouldFail = shouldFail
    }

    var uploadCount: Int { queue.sync { _uploadCount } }

    func upload(fileURL: URL, mimeType: String, progress: (@Sendable (Double) -> Void)?) async throws -> FileUploadResult {
        queue.sync { _uploadCount += 1 }
        if shouldFail {
            throw FileRepositoryError.transport(message: "boom")
        }
        return FileUploadResult(objectName: objectName)
    }
    func resolveDownloadURL(objectName: String?) -> URL? { nil }
    func download(objectName: String) async throws -> URL {
        throw FileRepositoryError.unsupportedScheme
    }
}

private final class StubUserRepository: UserRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.user.stub")
    private var _cached: UserProfile?
    private var _remote: UserProfile?
    private var _fetchCalls: [Bool] = []
    private var _updateAvatarCalls: [String] = []
    var error: APIError?
    var updateAvatarError: APIError?

    init(cached: UserProfile? = nil, remote: UserProfile? = nil) {
        self._cached = cached
        self._remote = remote ?? cached
    }

    var fetchCalls: [Bool] { queue.sync { _fetchCalls } }
    var updateAvatarCalls: [String] { queue.sync { _updateAvatarCalls } }

    func fetchProfile(forceRefresh: Bool) async throws -> UserProfile {
        queue.sync { _fetchCalls.append(forceRefresh) }
        if let error { throw error }
        guard let remote = queue.sync(execute: { _remote }) else {
            throw APIError.business(code: 50000, message: "no data")
        }
        queue.sync { _cached = remote }
        return remote
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        queue.sync { _cached = profile }
        return profile
    }

    func updateAvatar(_ avatar: String) async throws {
        queue.sync { _updateAvatarCalls.append(avatar) }
        if let updateAvatarError { throw updateAvatarError }
        queue.sync {
            var next = _cached ?? UserProfile()
            next.avatar = avatar
            _cached = next
        }
    }

    func cachedProfile() -> UserProfile? {
        queue.sync { _cached }
    }

    func clearCache() {
        queue.sync {
            _cached = nil
            _remote = nil
        }
    }
}
