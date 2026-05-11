import Foundation

@MainActor
public final class ContactsViewModel: ObservableObject {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    public enum SegmentTab: Hashable {
        case contacts
        case requests
    }

    @Published public var selectedTab: SegmentTab = .contacts
    @Published public private(set) var contacts: [ContactUser] = []
    @Published public private(set) var requests: [FriendRequest] = []
    @Published public private(set) var unreadRequestCount: Int64 = 0
    @Published public private(set) var contactsLoadState: LoadState = .idle
    @Published public private(set) var requestsLoadState: LoadState = .idle
    @Published public var transientMessage: String? = nil

    private let repository: ContactRepository

    public init(repository: ContactRepository) {
        self.repository = repository
    }

    /// 联系人列表里的真实好友（FRIEND）。
    public var friendContacts: [ContactUser] {
        contacts.filter { $0.relationStatus == .friend }
    }

    /// 「我已发起、待对方同意」的挂起项。
    public var pendingSentContacts: [ContactUser] {
        contacts.filter { $0.relationStatus == .pendingSent }
    }

    /// 联系人 tab badge：未读请求数（与 Android 主壳行为一致）。
    public var contactsTabBadgeCount: Int { Int(unreadRequestCount) }

    // MARK: - 加载

    public func loadAll() async {
        await loadContacts()
        await loadRequests()
        await refreshUnreadCount()
    }

    public func loadContacts() async {
        if case .loading = contactsLoadState { return }
        contactsLoadState = .loading
        do {
            contacts = try await repository.listContacts()
            contactsLoadState = .loaded
        } catch let api as APIError {
            contactsLoadState = .error(api.displayMessage)
        } catch {
            contactsLoadState = .error(error.localizedDescription)
        }
    }

    public func loadRequests() async {
        if case .loading = requestsLoadState { return }
        requestsLoadState = .loading
        do {
            requests = try await repository.listFriendRequests()
            requestsLoadState = .loaded
        } catch let api as APIError {
            requestsLoadState = .error(api.displayMessage)
        } catch {
            requestsLoadState = .error(error.localizedDescription)
        }
    }

    public func refreshUnreadCount() async {
        do {
            unreadRequestCount = try await repository.friendRequestCount()
        } catch {
            // badge 静默失败，不打扰用户。
            unreadRequestCount = Int64(requests.count)
        }
    }

    /// 切换到「请求」二级 tab：与 Android 行为一致——进入即视作已读，badge 清零。
    public func selectTab(_ tab: SegmentTab) async {
        selectedTab = tab
        if tab == .requests {
            unreadRequestCount = 0
            await loadRequests()
        }
    }

    // MARK: - 操作

    public func accept(_ request: FriendRequest) async {
        do {
            try await repository.acceptFriendRequest(requestId: request.requestId)
            requests.removeAll { $0.requestId == request.requestId }
            await loadContacts()
            await refreshUnreadCount()
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    public func reject(_ request: FriendRequest) async {
        do {
            try await repository.rejectFriendRequest(requestId: request.requestId)
            requests.removeAll { $0.requestId == request.requestId }
            await refreshUnreadCount()
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    public func remove(_ contact: ContactUser) async {
        do {
            try await repository.removeContact(userId: contact.userId)
            contacts.removeAll { $0.userId == contact.userId }
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch {
            transientMessage = error.localizedDescription
        }
    }

    public func sendFriendRequest(targetUserId: Int64) async -> Bool {
        do {
            try await repository.sendFriendRequest(targetUserId: targetUserId)
            await loadContacts()
            return true
        } catch let api as APIError {
            transientMessage = api.displayMessage
            return false
        } catch {
            transientMessage = error.localizedDescription
            return false
        }
    }

    public func search(keyword: String) async -> [ContactSearchUser] {
        do {
            return try await repository.search(keyword: keyword)
        } catch let api as APIError {
            transientMessage = api.displayMessage
        } catch {
            transientMessage = error.localizedDescription
        }
        return []
    }

    public func clearTransientMessage() {
        transientMessage = nil
    }
}
