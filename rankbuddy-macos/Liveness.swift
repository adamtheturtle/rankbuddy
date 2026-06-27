import AppKit
import BuddyAppKit
import Foundation
import UserNotifications

/// Opt-in "liveness" settings: a background sweep keeps a Dock-icon count of upcoming
/// (scheduled) interviews current even with no window open, mirroring PadBuddy's active-pads
/// badge + background refresher. Off by default — the user turns it on in General settings,
/// which is also where the system badge permission is requested.
enum LivenessSettings {
    /// `@AppStorage` key: whether the background sweep + Dock badge are enabled.
    static let backgroundUpdatesKey = "rb.backgroundUpdates"
    /// How often the background sweep runs.
    static let interval: Duration = .seconds(300)
}

/// Pure derivations for the liveness sweep, kept apart from the timer/badge side effects so
/// they're unit-testable.
enum LivenessDigest {
    /// The number of interviews currently in the "scheduled" (upcoming) state. Self-clearing:
    /// the count falls as interviews complete, so the badge needs no read-tracking.
    static func scheduledCount(_ interviews: [Interview]) -> Int {
        interviews.count(where: { $0.status.lowercased() == "scheduled" })
    }

    /// The Dock badge label for a count: `nil` (no badge) at zero, otherwise the number.
    static func badgeLabel(scheduledCount count: Int) -> String? {
        count > 0 ? String(count) : nil
    }
}

/// Keeps the Dock badge's scheduled-interview count fresh on a timer, independent of any
/// window. Normal use already refetches when a list loads; this closes the gap where the app
/// is left running with no window open while interviews change server-side.
@MainActor
final class LivenessMonitor {
    static let shared = LivenessMonitor()
    private var task: Task<Void, Never>?
    private init() {}

    /// Starts the sweep loop (idempotent). Runs one sweep immediately, then every interval.
    /// The loop always runs but self-gates on the opt-in each tick, so toggling the setting
    /// takes effect without restarting the timer.
    func start(store: AccountStore, every interval: Duration = LivenessSettings.interval) {
        guard task == nil else { return }

        task = Task { [weak self] in
            await self?.sweep(store: store)
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }

                await self?.sweep(store: store)
            }
        }
    }

    /// One sweep: when enabled, fetch the current account's interviews and badge the count of
    /// scheduled ones; when disabled (or for a demo/key-less account) clear the badge.
    func sweep(store: AccountStore) async {
        guard UserDefaults.standard.bool(forKey: LivenessSettings.backgroundUpdatesKey),
              let account = store.currentAccount, !account.isMock, !account.token.isEmpty,
              let interviews = try? await HackerRankClient(account: account).interviewsPage().items
        else {
            NSApp.dockTile.badgeLabel = nil
            return
        }

        NSApp.dockTile.badgeLabel = LivenessDigest.badgeLabel(
            scheduledCount: LivenessDigest.scheduledCount(interviews)
        )
    }

    /// Requests the system "badge" capability so `NSDockTile.badgeLabel` actually renders
    /// (macOS Monterey+ only draws it for an app granted `.badge`). Idempotent.
    func requestBadgeAuthorization() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) }
    }
}
