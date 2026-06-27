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
    /// `@AppStorage` key: whether to post a notification when new interviews appear.
    static let notifyKey = "rb.notifyNewInterviews"
    /// `@AppStorage` key: how often the background sweep runs, in minutes.
    static let intervalMinutesKey = "rb.refreshMinutes"
    /// The cadence options offered in Settings, in minutes.
    static let intervalOptions = [1, 2, 5, 10, 15, 30]
    /// The default sweep cadence in minutes.
    static let defaultIntervalMinutes = 5

    /// Clamps a raw stored minutes value to a supported option, falling back to the default for
    /// an unset (`0`) or unrecognised value. Pure, so it's unit-testable.
    static func intervalMinutes(raw: Int) -> Int {
        intervalOptions.contains(raw) ? raw : defaultIntervalMinutes
    }

    /// The current sweep cadence as a `Duration`, read from the stored setting.
    static func currentInterval() -> Duration {
        .seconds(intervalMinutes(raw: UserDefaults.standard.integer(forKey: intervalMinutesKey)) * 60)
    }

    /// Where the set of interview IDs last seen for an account is persisted, so the next sweep
    /// can tell which interviews are new.
    static func seenKey(_ accountID: UUID) -> String {
        "rb.liveness.seen.\(accountID.uuidString)"
    }
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

    /// The interviews in `current` that weren't seen on the previous sweep, so a notification
    /// reports only what's genuinely new.
    static func newInterviews(previousIDs: Set<String>, current: [Interview]) -> [Interview] {
        current.filter { !previousIDs.contains($0.id) }
    }

    /// The one-line body for a "new interviews" notification.
    static func notificationBody(newCount count: Int) -> String {
        count == 1 ? "1 new interview" : "\(count) new interviews"
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

    /// Starts the sweep loop (idempotent). Runs one sweep immediately, then re-reads the
    /// configured cadence before each subsequent sweep, so a changed interval (or toggled
    /// opt-in) takes effect without restarting the timer. Tests can pin the cadence via
    /// `interval`.
    func start(store: AccountStore, every interval: Duration? = nil) {
        guard task == nil else { return }

        task = Task { [weak self] in
            await self?.sweep(store: store)
            while !Task.isCancelled {
                try? await Task.sleep(for: interval ?? LivenessSettings.currentInterval())
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
        notifyIfNeeded(interviews, accountID: account.id)
    }

    /// Compares this sweep's interviews against the account's last-seen set, posting a
    /// notification for genuinely new ones. The first sweep only establishes the baseline (no
    /// notification), so enabling the feature never floods with the existing backlog.
    private func notifyIfNeeded(_ interviews: [Interview], accountID: UUID) {
        let currentIDs = Set(interviews.map(\.id))
        if let previous = loadSeen(accountID),
           UserDefaults.standard.bool(forKey: LivenessSettings.notifyKey) {
            let new = LivenessDigest.newInterviews(previousIDs: previous, current: interviews)
            if !new.isEmpty { LivenessNotifier.shared.notify(newCount: new.count) }
        }

        saveSeen(currentIDs, accountID: accountID)
    }

    private func loadSeen(_ accountID: UUID) -> Set<String>? {
        guard let data = UserDefaults.standard.data(forKey: LivenessSettings.seenKey(accountID)),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return nil }

        return Set(ids)
    }

    private func saveSeen(_ ids: Set<String>, accountID: UUID) {
        guard let data = try? JSONEncoder().encode(Array(ids)) else { return }

        UserDefaults.standard.set(data, forKey: LivenessSettings.seenKey(accountID))
    }

    /// Requests the system "badge" capability so `NSDockTile.badgeLabel` actually renders
    /// (macOS Monterey+ only draws it for an app granted `.badge`). Idempotent.
    func requestBadgeAuthorization() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) }
    }
}

/// Posts a single, coalescing macOS notification when new interviews appear (#23). Opt-in and
/// suppressed while the app is frontmost — you're already looking — so it only fires for
/// background activity. Tapping it brings the app forward on the Interviews section.
@MainActor
final class LivenessNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LivenessNotifier()
    private let center = UNUserNotificationCenter.current()
    /// One stable id so rapid bursts coalesce into a single alert rather than stacking.
    private static let notificationID = "rb.newInterviews"

    override private init() {
        super.init()
    }

    /// Wire up tap routing. Call once at launch.
    func register() {
        center.delegate = self
    }

    /// Ask for alert permission, deferred until the user opts in so the prompt appears when
    /// expected.
    func requestAuthorization() {
        Task { _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge]) }
    }

    /// Post a "new interviews" alert, unless the app is frontmost (you'd already see them).
    func notify(newCount: Int) {
        guard newCount > 0, !NSApp.isActive else { return }

        Task { await post(newCount: newCount) }
    }

    private func post(newCount: Int) async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard await (try? center.requestAuthorization(options: [.alert, .sound])) == true else { return }

        case .denied:
            return

        default:
            break
        }

        let content = UNMutableNotificationContent()
        content.title = "New interviews"
        content.body = LivenessDigest.notificationBody(newCount: newCount)
        content.sound = .default

        let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// On tap, route to the Interviews section (the same defaults write the deep links use) and
    /// bring the app forward.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive _: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            UserDefaults.standard.set(SidebarSection.interviews.rawValue, forKey: "selectedSection")
            NSApp.activate(ignoringOtherApps: true)
            completionHandler()
        }
    }
}
