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
    // periphery:ignore
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
    // periphery:ignore
    /// Mirrors favourites to iCloud when the capability is present; nil in demo mode (#22).
    @State private var favoritesSync: FavoritesSyncCoordinator?
    @State private var savedSearchSync: SavedSearchSyncCoordinator?
    @State private var preferenceSync: PreferenceSyncCoordinator?
    @State private var recentActivitySync: RecentActivitySyncCoordinator?
    /// The user's chosen appearance (General settings), applied to the main window.
    @AppStorage(AppAppearance.defaultsKey) private var appearance: AppAppearance = .system
    /// Where the app shows itself — Dock, Menu Bar, or both (#66). Drives the activation policy
    /// and whether the Menu Bar extra is inserted.
    @AppStorage(AppPresence.defaultsKey) private var presence: AppPresence = .both
    /// Explains a rejected activation-policy transition after restoring the prior safe presence.
    @State private var presenceError: String?
    /// Re-checks the current account's token so a mid-session revocation surfaces a banner (#40).
    @State private var health: AccountHealthMonitor

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
        let favoritesSync = isDemo
            ? nil
            : FavoritesSyncCoordinator(
                favorites: favorites,
                store: CloudSyncKeyValueStore(key: FavoritesSyncCoordinator.key),
                validAccountIDs: { Set(store.accounts.map(\.id.uuidString)) }
            )
        _favoritesSync = State(initialValue: favoritesSync)
        let savedSearchSync = isDemo
            ? nil
            : SavedSearchSyncCoordinator(store: CloudSyncKeyValueStore(key: SavedSearchSyncCoordinator.key))
        _savedSearchSync = State(initialValue: savedSearchSync)
        let preferenceSync = isDemo
            ? nil
            : PreferenceSyncCoordinator(store: CloudSyncKeyValueStore(key: PreferenceSyncCoordinator.key))
        _preferenceSync = State(initialValue: preferenceSync)
        let recentActivitySync = isDemo
            ? nil
            : RecentActivitySyncCoordinator(
                store: CloudSyncKeyValueStore(key: RecentActivitySyncCoordinator.key),
                accountIDs: { Set(store.accounts.map(\.id)) }
            )
        _recentActivitySync = State(initialValue: recentActivitySync)
        let health = AccountHealthMonitor()
        _health = State(initialValue: health)
        ApplicationStartup.start(
            syncServices: ApplicationSyncServices(
                favorites: favoritesSync,
                savedSearches: savedSearchSync,
                preferences: preferenceSync,
                recentActivity: recentActivitySync
            ),
            health: health,
            store: store
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
                .background(MainWindowRegistration())
                .task {
                    applyPresence(presence)
                }
                .onChange(of: presence) { old, new in applyPresence(new, rollback: old) }
                .alert("Couldn’t Change App Visibility", isPresented: presenceErrorPresented) {
                    Button("OK") { presenceError = nil }
                } message: {
                    Text(presenceError ?? "")
                }
                .preferredColorScheme(appearance.colorScheme)
        }
        .commands {
            AppCommands(palette: palette, openLink: openLink, commandContext: commandContext)
            #if canImport(Sparkle)
                UpdateCommands()
            #endif
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
                .environment(\.openURL, browserOpenURLAction)
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
                .environment(commandContext)
                .environment(\.openURL, browserOpenURLAction)
        }
    }

    /// Whether the Menu Bar extra is inserted, derived from and writing back to the same persisted
    /// presence preference. This keeps system/user removal in sync with Settings.
    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { presence.showsMenuBarIcon },
            set: {
                let updatedPresence = presence.settingMenuBarInserted($0)
                if updatedPresence != presence {
                    presence = updatedPresence
                }
            }
        )
    }

    private var presenceErrorPresented: Binding<Bool> {
        Binding(
            get: { presenceError != nil },
            set: {
                if !$0 {
                    presenceError = nil
                }
            }
        )
    }

    /// Applies a preference only when AppKit accepts it. A rejection restores the previous
    /// preference (or derives one from the actual startup policy) and keeps at least one surface.
    private func applyPresence(_ requested: AppPresence, rollback: AppPresence? = nil) {
        guard !requested.applyDockVisibility() else { return }

        let restored = rollback ?? requested.matchingActualPolicy(NSApp.activationPolicy())
        presence = restored
        presenceError = """
        macOS couldn’t switch RankBuddy to “\(requested.label)”. The setting was restored to \
        “\(restored.label)”. Try again after closing any system dialogs or restarting RankBuddy.
        """
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
