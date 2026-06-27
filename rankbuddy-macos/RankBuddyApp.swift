import BuddyAppKit
import SwiftUI

/// The RankBuddy app (launched by `RankBuddyEntryPoint` for the GUI path).
///
/// Uses a single, unique `Window` (rather than a `WindowGroup`) for the main
/// window so the app never opens duplicate main windows, plus a `Settings`
/// scene for preferences and account management.
struct RankBuddyApp: App {
    /// The app's single multi-account store, shared with every scene via the environment.
    @State private var accountStore: AccountStore
    /// Command-palette presentation state, shared with the menu commands.
    @State private var palette = PaletteModel()
    /// Account-aware favourites, shared with the lists and the palette (#25).
    @State private var favorites: FavoritesStore
    /// Mirrors favourites to iCloud when the capability is present; nil in demo mode (#22).
    @State private var favoritesSync: FavoritesSyncCoordinator?
    /// The user's chosen appearance (General settings), applied to the main window.
    @AppStorage(AppAppearance.defaultsKey) private var appearance: AppAppearance = .system
    /// Re-checks the current account's token so a mid-session revocation surfaces a banner (#40).
    @State private var health = AccountHealthMonitor()

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
        let favorites = FavoritesStore(isTesting: isDemo)
        _favorites = State(initialValue: favorites)
        // Sync real favourites to iCloud (gated on the capability inside the coordinator);
        // demo mode stays local-only.
        _favoritesSync = State(
            initialValue: isDemo
                ? nil
                : FavoritesSyncCoordinator(
                    favorites: favorites,
                    store: CloudSyncKeyValueStore(key: FavoritesSyncCoordinator.key)
                )
        )
    }

    var body: some Scene {
        Window("RankBuddy", id: WindowID.main) {
            ContentView()
                .environment(accountStore)
                .environment(palette)
                .environment(favorites)
                .environment(health)
                .task {
                    favoritesSync?.start()
                    NetworkMonitor.shared.start()
                    LivenessNotifier.shared.register()
                    LivenessMonitor.shared.start(store: accountStore)
                    health.start(store: accountStore)
                }
                .preferredColorScheme(appearance.colorScheme)
        }
        .commands {
            AppCommands(palette: palette)
            UpdateCommands()
        }

        Settings {
            SettingsView()
                .environment(accountStore)
                .environment(health)
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
