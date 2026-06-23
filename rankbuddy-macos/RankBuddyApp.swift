import SwiftUI

/// The RankBuddy app entry point.
///
/// Uses a single, unique `Window` (rather than a `WindowGroup`) for the main
/// window so the app never opens duplicate main windows, plus a `Settings`
/// scene for preferences and account management.
@main
struct RankBuddyApp: App {
    /// The app's single multi-account store, shared with every scene via the environment.
    @State private var accountStore: AccountStore
    /// The session HackerRank clients use — the demo mock or the real shared session.
    private let session: URLSession
    /// Command-palette presentation state, shared with the menu commands.
    @State private var palette = PaletteModel()

    init() {
        // Demo mode (RANKBUDDY_DEMO=1) seeds a demo account and serves bundled fixtures,
        // so the app shows populated views without a real token (#10).
        let isDemo = ProcessInfo.processInfo.environment["RANKBUDDY_DEMO"] == "1"
        session = isDemo ? .rankBuddyDemo : .shared
        let store = isDemo
            ? AccountStore.rankBuddy(isTesting: true, seed: [Account(label: "Demo (HackerRank)", token: "demo")])
            : AccountStore.rankBuddy()
        _accountStore = State(initialValue: store)
    }

    var body: some Scene {
        Window("RankBuddy", id: WindowID.main) {
            ContentView()
                .environment(accountStore)
                .environment(\.hackerRankSession, session)
                .environment(palette)
        }
        .commands {
            AppCommands(palette: palette)
        }

        Settings {
            SettingsView()
                .environment(accountStore)
                .environment(\.hackerRankSession, session)
        }
    }
}

/// Stable identifiers for the app's windows.
enum WindowID {
    static let main = "main"
}
