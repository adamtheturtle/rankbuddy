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
    /// Command-palette presentation state, shared with the menu commands.
    @State private var palette = PaletteModel()
    /// Account-aware favourites, shared with the lists and the palette (#25).
    @State private var favorites: FavoritesStore

    init() {
        // Demo mode (RANKBUDDY_DEMO=1) seeds the in-memory demo account; its `isMock` flag
        // routes its client to the bundled fixtures, so the app shows populated views
        // without a real token (#10). The mock is chosen per-account, not process-wide.
        let isDemo = ProcessInfo.processInfo.environment["RANKBUDDY_DEMO"] == "1"
        let store = isDemo
            ? AccountStore.rankBuddy(isTesting: true, seed: [.demo])
            : AccountStore.rankBuddy()
        _accountStore = State(initialValue: store)
        // Demo mode keeps favourites in-memory so it never reads or writes real favourites.
        _favorites = State(initialValue: FavoritesStore(isTesting: isDemo))
    }

    var body: some Scene {
        Window("RankBuddy", id: WindowID.main) {
            ContentView()
                .environment(accountStore)
                .environment(palette)
                .environment(favorites)
        }
        .commands {
            AppCommands(palette: palette)
        }

        Settings {
            SettingsView()
                .environment(accountStore)
        }

        MenuBarExtra("RankBuddy", systemImage: "checklist") {
            MenuBarContent()
                .environment(accountStore)
        }
    }
}

/// Stable identifiers for the app's windows.
enum WindowID {
    static let main = "main"
}
