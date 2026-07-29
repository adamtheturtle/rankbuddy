//
//  RankBuddyApp.swift
//  rankbuddy-macos
//

import BuddyAppKit
import SwiftUI

/// The RankBuddy app (launched by `RankBuddyEntryPoint` for the GUI path).
///
/// Uses a single, unique `Window` (rather than a `WindowGroup`) for the main
/// window so the app never opens duplicate main windows, plus a `Settings`
/// scene for preferences and account management.
struct RankBuddyApp: App {
    /// Provides the Dock right-click menu (#45).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// The app's single multi-account store, shared with every scene via the environment.
    @State private var accountStore: AccountStore
    /// Command-palette presentation state, shared with the menu commands.
    @State private var palette = PaletteModel()
    /// Open-by-URL sheet presentation state, shared with the File command (#42).
    @State private var openLink = OpenLinkModel()
    /// The active view's menu-addressable actions (#101).
    @State private var commandContext = AppCommandContext()
    /// Account-aware favourites, shared with the lists and the palette (#25).
    @State private var favorites: FavoritesStore
    /// Mirrors favourites to iCloud when the capability is present; nil in demo mode (#22).
    @State private var favoritesSync: FavoritesSyncCoordinator?
    /// The user's chosen appearance (General settings), applied to the main window.
    @AppStorage(AppAppearance.defaultsKey) private var appearance: AppAppearance = .system
    /// Where the app shows itself — Dock, Menu Bar, or both (#66). Drives the activation policy
    /// and whether the Menu Bar extra is inserted.
    @AppStorage(AppPresence.defaultsKey) private var presence: AppPresence = .both
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
        // Hand the single live store to the Focus-filter intent (#96), which runs in-process
        // and must drive the same selection the UI observes rather than a detached copy.
        SharedAccountStore.shared = store
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
                .environment(openLink)
                .environment(commandContext)
                .environment(favorites)
                .environment(health)
                .environment(\.openURL, browserOpenURLAction)
                .task {
                    favoritesSync?.start()
                    NetworkMonitor.shared.start()
                    LivenessNotifier.shared.register()
                    LivenessMonitor.shared.start(store: accountStore)
                    health.start(store: accountStore)
                    presence.applyDockVisibility()
                }
                .onChange(of: presence) { _, new in new.applyDockVisibility() }
                .preferredColorScheme(appearance.colorScheme)
        }
        .commands {
            AppCommands(palette: palette, openLink: openLink, commandContext: commandContext)
            UpdateCommands()
        }

        // Opens a single item in its own window (#49). Keyed by a Codable detail value passed
        // through openWindow(value:).
        WindowGroup(id: WindowID.detail, for: DetailWindowValue.self) { $value in
            DetailWindowContent(value: value)
                .environment(accountStore)
                .environment(favorites)
                .environment(commandContext)
                .environment(\.openURL, browserOpenURLAction)
                .preferredColorScheme(appearance.colorScheme)
        }

        // The account activity feed (audit log) lives in its own window rather than a Settings
        // tab (#115), opened from the Window menu. A single unique window, like the main one.
        Window("Account Activity", id: WindowID.activity) {
            AccountActivityView()
                .environment(accountStore)
                .environment(\.openURL, browserOpenURLAction)
                .preferredColorScheme(appearance.colorScheme)
        }
        .commands {
            AccountActivityCommands()
        }

        // The MCP tool-call activity log in its own window (mirroring PadBuddy), opened from
        // Settings ▸ MCP. A single unique window, like the others.
        Window("MCP Activity", id: WindowID.mcpActivity) {
            MCPActivityView()
                .preferredColorScheme(appearance.colorScheme)
        }
        .defaultSize(width: 480, height: 460)

        Settings {
            SettingsView()
                .environment(accountStore)
                .environment(health)
                .preferredColorScheme(appearance.colorScheme)
        }
        .commands {
            // Adds the standard View > Show/Hide Toolbar and Customize Toolbar... items (#107),
            // which drive the customizable list toolbar (#101).
            ToolbarCommands()
        }

        MenuBarExtra("RankBuddy", systemImage: "checklist", isInserted: menuBarInserted) {
            MenuBarContent()
                .environment(accountStore)
        }
    }

    /// Whether the Menu Bar extra is inserted, derived from and writing back to the same persisted
    /// presence preference. This keeps system/user removal in sync with Settings.
    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { presence.showsMenuBarIcon },
            set: { presence = presence.settingMenuBarInserted($0) }
        )
    }

    /// Routes every SwiftUI `Link` / `openURL` through the browser preferences (#63), so web
    /// links honour the chosen browser and background-open setting. Deep links use their own
    /// routing and are unaffected.
    private var browserOpenURLAction: OpenURLAction {
        OpenURLAction { url in
            BrowserSettings.open(url)
            return .handled
        }
    }
}

/// Stable identifiers for the app's windows.
enum WindowID {
    static let main = "main"
    /// The standalone item-detail window (#49).
    static let detail = "detail"
    /// The account activity (audit log) window (#115).
    static let activity = "activity"
    /// The MCP tool-call activity log window, opened from Settings ▸ MCP.
    static let mcpActivity = "mcp-activity"
}
