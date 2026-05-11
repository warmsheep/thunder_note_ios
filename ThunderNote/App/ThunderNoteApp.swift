import SwiftUI

@main
struct ThunderNoteApp: App {
    init() {
        CacheVersionMigrator.shared.migrateIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
