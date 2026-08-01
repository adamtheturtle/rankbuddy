//
//  ApplicationStartup.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation

nonisolated struct ApplicationStartupGate {
    private var hasStarted = false

    mutating func claim() -> Bool {
        guard !hasStarted else { return false }

        hasStarted = true
        return true
    }
}

/// Starts process-wide services independently of whether SwiftUI creates the main window.
@MainActor
enum ApplicationStartup {
    private static var gate = ApplicationStartupGate()
    private static let presenceMonitor = AppPresenceMonitor()

    static func start(
        favoritesSync: FavoritesSyncCoordinator?,
        savedSearchSync: SavedSearchSyncCoordinator?,
        preferenceSync: PreferenceSyncCoordinator?,
        health: AccountHealthMonitor,
        store: AccountStore
    ) {
        guard gate.claim() else { return }

        favoritesSync?.start()
        savedSearchSync?.start()
        preferenceSync?.start()
        NetworkMonitor.shared.start()
        LivenessNotifier.shared.register()
        LivenessMonitor.shared.start(store: store)
        health.start(store: store)
        presenceMonitor.start()
    }
}
