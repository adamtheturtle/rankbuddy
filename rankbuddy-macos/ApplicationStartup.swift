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

@MainActor
struct ApplicationSyncServices {
    let favorites: FavoritesSyncCoordinator?
    let savedSearches: SavedSearchSyncCoordinator?
    let preferences: PreferenceSyncCoordinator?
    let recentActivity: RecentActivitySyncCoordinator?

    func start() {
        favorites?.start()
        savedSearches?.start()
        preferences?.start()
        recentActivity?.start()
    }
}

/// Starts process-wide services independently of whether SwiftUI creates the main window.
@MainActor
enum ApplicationStartup {
    private static var gate = ApplicationStartupGate()
    private static let presenceMonitor = AppPresenceMonitor()

    static func start(
        syncServices: ApplicationSyncServices,
        health: AccountHealthMonitor,
        store: AccountStore
    ) {
        guard gate.claim() else { return }

        syncServices.start()
        NetworkMonitor.shared.start()
        LivenessNotifier.shared.register()
        LivenessMonitor.shared.start(store: store)
        health.start(store: store)
        presenceMonitor.start()
    }
}
