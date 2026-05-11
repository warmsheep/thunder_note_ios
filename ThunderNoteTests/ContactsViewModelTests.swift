import XCTest
@testable import ThunderNote

final class ContactsViewModelTests: XCTestCase {
    @MainActor
    func test_loadAll_populatesContactsAndRequests() async {
        let repo = StubContactRepository(
            contacts: [
                ContactUser(userId: 1, username: "a", relationStatus: .friend),
                ContactUser(userId: 2, username: "b", relationStatus: .pendingSent)
            ],
            requests: [FriendRequest(requestId: 11, userId: 3, username: "c")],
            unreadCount: 1
        )
        let vm = ContactsViewModel(repository: repo)
        await vm.loadAll()
        XCTAssertEqual(vm.contacts.count, 2)
        XCTAssertEqual(vm.friendContacts.count, 1)
        XCTAssertEqual(vm.pendingSentContacts.count, 1)
        XCTAssertEqual(vm.requests.count, 1)
        XCTAssertEqual(vm.unreadRequestCount, 1)
        XCTAssertEqual(vm.contactsTabBadgeCount, 1)
    }

    @MainActor
    func test_selectRequestsTab_clearsBadge() async {
        let repo = StubContactRepository(
            contacts: [],
            requests: [FriendRequest(requestId: 11)],
            unreadCount: 5
        )
        let vm = ContactsViewModel(repository: repo)
        await vm.refreshUnreadCount()
        XCTAssertEqual(vm.contactsTabBadgeCount, 5)

        await vm.selectTab(.requests)

        XCTAssertEqual(vm.selectedTab, .requests)
        XCTAssertEqual(vm.contactsTabBadgeCount, 0, "进入请求 tab 后徽标即清零")
    }

    @MainActor
    func test_accept_removesRequestAndReloadsContacts() async {
        let repo = StubContactRepository(
            contacts: [],
            requests: [FriendRequest(requestId: 11)],
            unreadCount: 1
        )
        let vm = ContactsViewModel(repository: repo)
        await vm.loadAll()
        XCTAssertEqual(vm.requests.count, 1)

        // 让 accept 之后的 listContacts 返回新好友
        repo.setNextContacts([ContactUser(userId: 99, username: "new", relationStatus: .friend)])

        await vm.accept(vm.requests[0])

        XCTAssertEqual(repo.acceptedIds, [11])
        XCTAssertEqual(vm.requests.count, 0, "请求列表本地立即移除")
        XCTAssertEqual(vm.contacts.first?.userId, 99, "联系人列表刷新")
    }

    @MainActor
    func test_reject_removesRequest() async {
        let repo = StubContactRepository(
            contacts: [],
            requests: [FriendRequest(requestId: 11)],
            unreadCount: 1
        )
        let vm = ContactsViewModel(repository: repo)
        await vm.loadAll()
        await vm.reject(vm.requests[0])
        XCTAssertEqual(repo.rejectedIds, [11])
        XCTAssertEqual(vm.requests.count, 0)
    }

    @MainActor
    func test_remove_dropsContactLocally() async {
        let repo = StubContactRepository(
            contacts: [
                ContactUser(userId: 1, username: "a", relationStatus: .friend)
            ],
            requests: [],
            unreadCount: 0
        )
        let vm = ContactsViewModel(repository: repo)
        await vm.loadAll()
        await vm.remove(vm.contacts[0])
        XCTAssertEqual(repo.removedUserIds, [1])
        XCTAssertEqual(vm.contacts.count, 0)
    }

    @MainActor
    func test_sendFriendRequest_returnsTrueOnSuccess() async {
        let repo = StubContactRepository(contacts: [], requests: [], unreadCount: 0)
        let vm = ContactsViewModel(repository: repo)
        let ok = await vm.sendFriendRequest(targetUserId: 42)
        XCTAssertTrue(ok)
        XCTAssertEqual(repo.sentTargetIds, [42])
    }
}

// MARK: - Stub Repository

private final class StubContactRepository: ContactRepository, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.contact.stub")
    private var _contacts: [ContactUser]
    private var _requests: [FriendRequest]
    private var _unreadCount: Int64
    private var _nextContacts: [ContactUser]?
    private var _accepted: [Int64] = []
    private var _rejected: [Int64] = []
    private var _removed: [Int64] = []
    private var _sent: [Int64] = []

    init(contacts: [ContactUser], requests: [FriendRequest], unreadCount: Int64) {
        self._contacts = contacts
        self._requests = requests
        self._unreadCount = unreadCount
    }

    func setNextContacts(_ value: [ContactUser]) {
        queue.sync { _nextContacts = value }
    }

    var acceptedIds: [Int64] { queue.sync { _accepted } }
    var rejectedIds: [Int64] { queue.sync { _rejected } }
    var removedUserIds: [Int64] { queue.sync { _removed } }
    var sentTargetIds: [Int64] { queue.sync { _sent } }

    func listContacts() async throws -> [ContactUser] {
        queue.sync {
            if let next = _nextContacts {
                _contacts = next
                _nextContacts = nil
            }
            return _contacts
        }
    }

    func listFriendRequests() async throws -> [FriendRequest] { queue.sync { _requests } }
    func friendRequestCount() async throws -> Int64 { queue.sync { _unreadCount } }

    func sendFriendRequest(targetUserId: Int64) async throws {
        queue.sync { _sent.append(targetUserId) }
    }

    func acceptFriendRequest(requestId: Int64) async throws {
        queue.sync { _accepted.append(requestId) }
    }

    func rejectFriendRequest(requestId: Int64) async throws {
        queue.sync { _rejected.append(requestId) }
    }

    func cancelOutgoingRequest(requestId: Int64) async throws {}

    func removeContact(userId: Int64) async throws {
        queue.sync { _removed.append(userId) }
    }

    func search(keyword: String) async throws -> [ContactSearchUser] { [] }
}
