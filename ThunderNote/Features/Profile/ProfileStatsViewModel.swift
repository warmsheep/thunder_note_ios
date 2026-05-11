import Foundation
import SwiftUI

/// D2-I6-08 我的页统计数。
///
/// 与 Android `ProfileOpsHelper.loadRecordCount + resolveFlashNoteCount + resolveFavoriteCount` 对齐：
/// - 闪记数：`FlashNoteRepository.list().count`（含收集箱）
/// - 收藏数：`FavoriteRepository.list().count`
/// - 记录数：`GET /api/messages/count` (Android `messageService.countMessages()`)
/// - 三个值都缓存到 `UserDefaults` key `tn.profile.stats.<username>`，冷启动直接展示缓存。
@MainActor
public final class ProfileStatsViewModel: ObservableObject {
    public struct Stats: Codable, Sendable, Equatable {
        public var flashNoteCount: Int
        public var favoriteCount: Int
        public var recordCount: Int64

        public init(flashNoteCount: Int = 0, favoriteCount: Int = 0, recordCount: Int64 = 0) {
            self.flashNoteCount = flashNoteCount
            self.favoriteCount = favoriteCount
            self.recordCount = recordCount
        }
    }

    public static let cacheKeyPrefix = "tn.profile.stats."

    @Published public private(set) var stats: Stats
    @Published public private(set) var isLoading: Bool = false

    private let flashNoteRepository: FlashNoteRepository
    private let favoriteRepository: FavoriteRepository
    private let messageRepository: MessageRepository
    private let userDefaults: UserDefaults
    private let usernameProvider: @Sendable () -> String?

    public init(
        flashNoteRepository: FlashNoteRepository,
        favoriteRepository: FavoriteRepository,
        messageRepository: MessageRepository,
        userDefaults: UserDefaults = .standard,
        usernameProvider: @Sendable @escaping () -> String?
    ) {
        self.flashNoteRepository = flashNoteRepository
        self.favoriteRepository = favoriteRepository
        self.messageRepository = messageRepository
        self.userDefaults = userDefaults
        self.usernameProvider = usernameProvider
        self.stats = Self.loadCached(userDefaults: userDefaults, username: usernameProvider()) ?? Stats()
    }

    public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        async let notes = (try? flashNoteRepository.list()) ?? []
        async let favorites = (try? favoriteRepository.list()) ?? []
        async let recordCount = (try? messageRepository.countMessages()) ?? Int64(0)

        let next = Stats(
            flashNoteCount: (await notes).count,
            favoriteCount: (await favorites).count,
            recordCount: await recordCount
        )
        stats = next
        Self.persistCached(userDefaults: userDefaults, username: usernameProvider(), stats: next)
    }

    public func clearCache() {
        let username = usernameProvider()
        if let username, !username.isEmpty {
            userDefaults.removeObject(forKey: Self.cacheKey(for: username))
        }
        stats = Stats()
    }

    // MARK: - 缓存

    static func cacheKey(for username: String) -> String {
        cacheKeyPrefix + username
    }

    private static func loadCached(userDefaults: UserDefaults, username: String?) -> Stats? {
        guard let username, !username.isEmpty else { return nil }
        guard let data = userDefaults.data(forKey: cacheKey(for: username)) else { return nil }
        return try? JSONDecoder.tnDefault.decode(Stats.self, from: data)
    }

    private static func persistCached(userDefaults: UserDefaults, username: String?, stats: Stats) {
        guard let username, !username.isEmpty else { return }
        guard let data = try? JSONEncoder.tnDefault.encode(stats) else { return }
        userDefaults.set(data, forKey: cacheKey(for: username))
    }
}
