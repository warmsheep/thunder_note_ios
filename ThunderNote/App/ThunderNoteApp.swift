import SwiftUI

@main
struct ThunderNoteApp: App {
    @StateObject private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(dependencies)
                .environmentObject(dependencies.session)
                .environmentObject(dependencies.authViewModel)
                .environmentObject(dependencies.serverConfigObservable)
                .task {
                    dependencies.bootstrap()
                }
        }
    }
}
