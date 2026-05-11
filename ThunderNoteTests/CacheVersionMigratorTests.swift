import XCTest
@testable import ThunderNote

final class CacheVersionMigratorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var temporaryDirectory: URL!
    private var fileManager: FileManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "tn.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults)
        fileManager = .default
        temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: temporaryDirectory)
        try super.tearDownWithError()
    }

    func test_migrateIfNeeded_storesCurrentVersion_onFirstRun() {
        let migrator = CacheVersionMigrator(userDefaults: defaults, fileManager: fileManager)
        XCTAssertEqual(migrator.lastAppliedVersion, 0)

        migrator.migrateIfNeeded()

        XCTAssertEqual(migrator.lastAppliedVersion, CacheVersionMigrator.currentCacheVersion)
    }

    func test_migrateIfNeeded_isIdempotent_whenAlreadyApplied() {
        defaults.set(CacheVersionMigrator.currentCacheVersion, forKey: CacheVersionMigrator.userDefaultsKey)
        let migrator = CacheVersionMigrator(userDefaults: defaults, fileManager: fileManager)

        migrator.migrateIfNeeded()
        migrator.migrateIfNeeded()

        XCTAssertEqual(migrator.lastAppliedVersion, CacheVersionMigrator.currentCacheVersion)
    }

    func test_reset_clearsRecordedVersion() {
        let migrator = CacheVersionMigrator(userDefaults: defaults, fileManager: fileManager)
        migrator.migrateIfNeeded()
        XCTAssertEqual(migrator.lastAppliedVersion, CacheVersionMigrator.currentCacheVersion)

        migrator.reset()

        XCTAssertEqual(migrator.lastAppliedVersion, 0)
    }
}
