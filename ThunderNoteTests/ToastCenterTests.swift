import XCTest
@testable import ThunderNote

final class ToastCenterTests: XCTestCase {

    /// 同 key 在 window 内只弹一次，第二次被丢弃。
    @MainActor
    func test_show_sameKeyWithinWindow_isThrottled() {
        let now = MutableNow(seconds: 1000)
        let center = ToastCenter(now: now.closure)

        XCTAssertTrue(center.show(key: "k", message: "第一次", window: 2.0))
        XCTAssertNotNil(center.currentToast)
        center.dismissCurrent()

        now.advance(by: 1.0) // 仍在 2s 窗口内
        XCTAssertFalse(center.show(key: "k", message: "第二次", window: 2.0))
        XCTAssertNil(center.currentToast)
    }

    /// 同 key 跨 window 后允许再次显示。
    @MainActor
    func test_show_sameKeyAfterWindow_isAllowed() {
        let now = MutableNow(seconds: 1000)
        let center = ToastCenter(now: now.closure)

        XCTAssertTrue(center.show(key: "k", message: "第一次", window: 2.0))
        center.dismissCurrent()

        now.advance(by: 3.0)
        XCTAssertTrue(center.show(key: "k", message: "再次", window: 2.0))
        XCTAssertEqual(center.currentToast?.message, "再次")
    }

    /// 不同 key 互不影响。
    @MainActor
    func test_show_differentKeys_areIndependent() {
        let center = ToastCenter()

        XCTAssertTrue(center.show(key: "a", message: "AAA"))
        center.dismissCurrent()
        XCTAssertTrue(center.show(key: "b", message: "BBB"))
    }

    /// 网络类错误关键字一律丢弃，不进入 currentToast。
    @MainActor
    func test_show_networkErrorMessages_areDropped() {
        let center = ToastCenter()

        let networkMessages = [
            "Network error: 连接超时",
            "Failed to connect to host",
            "Unable to resolve host \"example.com\"",
            "Request timed out",
            "Connection reset by peer",
            "Connection refused",
            "Software caused connection abort",
            "Failed to fetch profile",
            "获取资料失败"
        ]
        for message in networkMessages {
            XCTAssertFalse(
                center.show(key: "Net:\(message)", message: message),
                "网络错误应被丢弃：\(message)"
            )
        }
        XCTAssertNil(center.currentToast)
    }

    /// 空白消息直接丢弃。
    @MainActor
    func test_show_blankMessage_isDropped() {
        let center = ToastCenter()
        XCTAssertFalse(center.show(key: "k", message: "   \n  "))
        XCTAssertNil(center.currentToast)
    }

    /// isLikelyNetworkIssue 关键字大小写/前后空白不敏感。
    func test_isLikelyNetworkIssue_caseAndWhitespaceInsensitive() {
        XCTAssertTrue(ToastCenter.isLikelyNetworkIssue("  NETWORK ERROR  "))
        XCTAssertTrue(ToastCenter.isLikelyNetworkIssue("Operation TIMED OUT"))
        XCTAssertFalse(ToastCenter.isLikelyNetworkIssue("业务错误"))
        XCTAssertFalse(ToastCenter.isLikelyNetworkIssue(""))
    }

    /// dismissCurrent 清空 currentToast。
    @MainActor
    func test_dismissCurrent_clearsToast() {
        let center = ToastCenter()
        _ = center.show(key: "k", message: "hi")
        XCTAssertNotNil(center.currentToast)
        center.dismissCurrent()
        XCTAssertNil(center.currentToast)
    }
}

private final class MutableNow: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.tests.toast.mutablenow")
    private var seconds: TimeInterval
    init(seconds: TimeInterval) { self.seconds = seconds }
    func advance(by delta: TimeInterval) { queue.sync { self.seconds += delta } }
    var closure: @Sendable () -> Date {
        { [self] in Date(timeIntervalSince1970: self.queue.sync { self.seconds }) }
    }
}
