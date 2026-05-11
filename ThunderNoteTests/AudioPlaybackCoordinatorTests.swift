import XCTest
@testable import ThunderNote

final class AudioPlaybackCoordinatorTests: XCTestCase {
    func test_notifyDidStartPlaying_postsNotificationWithPlayerId() {
        let coordinator = AudioPlaybackCoordinator()
        let expectation = expectation(description: "received")
        let observer = NotificationCenter.default.addObserver(
            forName: AudioPlaybackCoordinator.didStartPlayingNotification,
            object: nil,
            queue: nil
        ) { note in
            let id = note.userInfo?[AudioPlaybackCoordinator.playerIdKey] as? String
            XCTAssertEqual(id, "alpha")
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        coordinator.notifyDidStartPlaying(playerId: "alpha")

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(coordinator.currentPlayerId, "alpha")
    }

    func test_notifyDidStopPlaying_clearsCurrentIdWhenMatching() {
        let coordinator = AudioPlaybackCoordinator()
        coordinator.notifyDidStartPlaying(playerId: "alpha")
        coordinator.notifyDidStopPlaying(playerId: "beta") // 不匹配，不应清掉
        XCTAssertEqual(coordinator.currentPlayerId, "alpha")
        coordinator.notifyDidStopPlaying(playerId: "alpha")
        XCTAssertNil(coordinator.currentPlayerId)
    }

    func test_stopAll_postsStopNotification() {
        let coordinator = AudioPlaybackCoordinator()
        coordinator.notifyDidStartPlaying(playerId: "alpha")

        let expectation = expectation(description: "stopAll")
        let observer = NotificationCenter.default.addObserver(
            forName: AudioPlaybackCoordinator.didStopAllNotification,
            object: nil,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        coordinator.stopAll()

        wait(for: [expectation], timeout: 1)
        XCTAssertNil(coordinator.currentPlayerId)
    }
}
