import SwiftUI

@main
struct VSTEP_Writing_for_WatchApp: App {
    init() {
        // Must activate on init, not onAppear
        WatchSessionManager.shared.activateSession()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.colorScheme, .light)
        }
    }
}
