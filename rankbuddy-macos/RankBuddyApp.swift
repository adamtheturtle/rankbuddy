import SwiftUI

/// The RankBuddy app entry point.
///
/// Uses a single, unique `Window` (rather than a `WindowGroup`) for the main
/// window so the app never opens duplicate main windows, plus a `Settings`
/// scene for preferences and account management.
@main
struct RankBuddyApp: App {
    /// The app's single multi-account store, shared with every scene via the environment.
    @State private var accountStore = AccountStore.rankBuddy()

    var body: some Scene {
        Window("RankBuddy", id: WindowID.main) {
            ContentView()
                .environment(accountStore)
        }

        Settings {
            SettingsView()
                .environment(accountStore)
        }
    }
}

/// Stable identifiers for the app's windows.
enum WindowID {
    static let main = "main"
}
