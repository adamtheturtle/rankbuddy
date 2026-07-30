//
//  Liveness.swift
//  rankbuddy-macos
//

import AppKit
import AsyncAlgorithms
import BuddyAppKit
import Foundation
import HackerRankKit
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
    /// `@AppStorage` key: which accounts the Dock badge counts (#68).
    static let dockScopeKey = "rb.dockBadgeScope"

    /// The Dock-badge scope as stored, defaulting to the current account (the historical
    /// behaviour) for an unset or unrecognised value.
    static func dockBadgeScope() -> DockBadgeScope {
        DockBadgeScope(rawValue: UserDefaults.standard.string(forKey: dockScopeKey) ?? "") ?? .currentAccount
    }

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

/// Which accounts the Dock badge's scheduled-interview count covers (#68). Matters with
/// multiple accounts: "all accounts" sums upcoming interviews across every real account,
/// while "current account" counts only the selected one. `RawRepresentable`/`String` so it
/// persists directly through `@AppStorage`.
enum DockBadgeScope: String, CaseIterable, Identifiable {
    case currentAccount
    case allAccounts

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .currentAccount: "Current account"
        case .allAccounts: "All accounts"
        }
    }

    /// The accounts this scope badges: real (non-demo) accounts with a token. "Current"
    /// narrows to the selected account; "all" spans every usable account.
    func badgeableAccounts(in store: AccountStore) -> [Account] {
        let usable: (Account) -> Bool = { !$0.isMock && !$0.token.isEmpty }
        switch self {
        case .currentAccount: return [store.currentAccount].compactMap(\.self).filter(usable)
        case .allAccounts: return store.accounts.filter(usable)
        }
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

    /// Sums a scope only when every account has a known count. A failed first refresh must not
    /// replace an existing Dock badge with a misleading partial total.
    static func scheduledTotal(accountIDs: [UUID], lastKnown: [UUID: Int]) -> Int? {
        guard accountIDs.allSatisfy({ lastKnown[$0] != nil }) else { return nil }

        return accountIDs.reduce(0) { $0 + (lastKnown[$1] ?? 0) }
    }

    /// The interviews in `current` that weren't seen on the previous sweep, so a notification
    /// reports only what's genuinely new and still actionable. Terminal or unknown records remain
    /// part of the saved baseline but never trigger an alert.
    static func newInterviews(previousIDs: Set<String>, current: [Interview]) -> [Interview] {
        current.filter {
            !previousIDs.contains($0.id) && isNotificationEligible(status: $0.status)
        }
    }

    /// Statuses for interviews a recruiter can still act on. Backend spelling variants normalize
    /// underscores/hyphens and whitespace before comparison.
    static func isNotificationEligible(status: String) -> Bool {
        let normalized = status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return ["scheduled", "upcoming", "live", "in progress", "ongoing"].contains(normalized)
    }

    /// The one-line body for a "new interviews" notification.
    static func notificationBody(newCount count: Int) -> String {
        count == 1 ? "1 new interview" : "\(count) new interviews"
    }
}

/// Concurrent, independently timed account probes for the liveness sweep. The scheduler admits a
/// bounded number at once and yields each healthy result immediately rather than waiting for the
/// slowest tenant.
enum LivenessProbe {
    static let concurrencyLimit = 4
    static let timeout: Duration = .seconds(15)

    nonisolated struct Result {
        let accountID: UUID
        let interviews: [Interview]
    }

    nonisolated static func interviews(account: Account, timeout: Duration) async -> [Interview]? {
        await withTaskGroup(of: [Interview]?.self) { group in
            group.addTask {
                try? await HackerRankClient(account: account).interviewsPage().items
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }

            let first = await group.next()
            group.cancelAll()
            return first.flatMap(\.self)
        }
    }

    /// Runs at most `limit` operations concurrently and publishes successful results in completion
    /// order, continuously admitting queued work as slots become available.
    nonisolated static func forEachResult<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        limit: Int,
        operation: @escaping @Sendable (Input) async -> Output?,
        onResult: @escaping @MainActor (Output) -> Void
    ) async {
        guard limit > 0 else { return }

        await withTaskGroup(of: Output?.self) { group in
            var iterator = inputs.makeIterator()
            for _ in 0 ..< min(limit, inputs.count) {
                guard let input = iterator.next() else { break }

                group.addTask { await operation(input) }
            }

            while let output = await group.next() {
                if let output {
                    await onResult(output)
                }
                if let input = iterator.next() {
                    group.addTask { await operation(input) }
                }
            }
        }
    }
}

/// Keeps the Dock badge's scheduled-interview count fresh on a timer, independent of any
/// window. Normal use already refetches when a list loads; this closes the gap where the app
/// is left running with no window open while interviews change server-side.
@MainActor
final class LivenessMonitor {
    static let shared = LivenessMonitor()
    private var loop: Task<Void, Never>?
    private var scheduledByAccount: [UUID: Int] = [:]
    private init() {}

    /// Starts the sweep loop (idempotent). Runs one sweep immediately, then re-reads the
    /// configured cadence before each subsequent sweep, so a changed interval (or toggled
    /// opt-in) takes effect without restarting the timer. Tests can pin the cadence via
    /// `interval`.
    func start(store: AccountStore, every interval: Duration? = nil) {
        guard loop == nil else { return }

        loop = Task { [weak self] in
            await self?.sweep(store: store)

            while !Task.isCancelled {
                let nextInterval = interval ?? LivenessSettings.currentInterval()
                for await _ in AsyncTimerSequence.repeating(every: nextInterval) {
                    guard !Task.isCancelled else { return }

                    await self?.sweep(store: store)
                    break
                }
            }
        }
    }

    /// One sweep: when enabled, fetch the in-scope accounts' interviews and badge the total
    /// count of scheduled ones (#68); when disabled (or with no usable account in scope) clear
    /// the badge. New-interview notifications stay per-account.
    func sweep(store: AccountStore) async {
        guard UserDefaults.standard.bool(forKey: LivenessSettings.backgroundUpdatesKey) else {
            scheduledByAccount.removeAll()
            DockBadge.set(count: 0)
            return
        }

        let accounts = LivenessSettings.dockBadgeScope().badgeableAccounts(in: store)
        guard !accounts.isEmpty else {
            DockBadge.set(count: 0)
            return
        }

        await LivenessProbe.forEachResult(
            accounts,
            limit: LivenessProbe.concurrencyLimit,
            operation: { account -> LivenessProbe.Result? in
                guard let interviews = await LivenessProbe.interviews(
                    account: account,
                    timeout: LivenessProbe.timeout
                ) else { return nil }

                return LivenessProbe.Result(accountID: account.id, interviews: interviews)
            },
            onResult: { [weak self] (result: LivenessProbe.Result) in
                guard let self else { return }

                scheduledByAccount[result.accountID] = LivenessDigest.scheduledCount(result.interviews)
                notifyIfNeeded(result.interviews, accountID: result.accountID)
                updateBadge(accounts: accounts)
            }
        )
    }

    private func updateBadge(accounts: [Account]) {
        guard let scheduled = LivenessDigest.scheduledTotal(
            accountIDs: accounts.map(\.id),
            lastKnown: scheduledByAccount
        ) else { return }

        DockBadge.set(count: scheduled)
    }

    /// Compares this sweep's interviews against the account's last-seen set, posting a
    /// notification for genuinely new ones. The first sweep only establishes the baseline (no
    /// notification), so enabling the feature never floods with the existing backlog.
    private func notifyIfNeeded(_ interviews: [Interview], accountID: UUID) {
        let currentIDs = Set(interviews.map(\.id))
        if let previous = loadSeen(accountID),
           UserDefaults.standard.bool(forKey: LivenessSettings.notifyKey) {
            let new = LivenessDigest.newInterviews(previousIDs: previous, current: interviews)
            if !new.isEmpty {
                LivenessNotifier.shared.notify(interviews: new, accountID: accountID)
            }
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
    func notify(interviews: [Interview], accountID: UUID) {
        guard let target = interviews.first, !NSApp.isActive else { return }

        Task { await post(newCount: interviews.count, accountID: accountID, interviewID: target.id) }
    }

    private func post(newCount: Int, accountID: UUID, interviewID: String) async {
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
        content.userInfo = Self.notificationUserInfo(accountID: accountID, interviewID: interviewID)

        let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// On tap, route to the Interviews section (the same defaults write the deep links use) and
    /// bring the app forward.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: () -> Void
    ) {
        let target = RankBuddyUserActivity.target(userInfo: response.notification.request.content.userInfo)
        Task { @MainActor in
            MainWindowPresenter.shared.show()
            if let target {
                let store = SharedAccountStore.resolve()
                if let accountID = UUID(uuidString: target.accountID),
                   store.accounts.contains(where: { $0.id == accountID }) {
                    store.showAllAccounts = false
                    store.currentAccountID = accountID
                }
                RankBuddyDeepLink.open(
                    collection: target.collection,
                    accountID: target.accountID,
                    itemID: target.itemID
                )
            } else {
                UserDefaults.standard.set(SidebarSection.interviews.rawValue, forKey: "selectedSection")
            }
        }
        completionHandler()
    }

    nonisolated static func notificationUserInfo(accountID: UUID, interviewID: String) -> [AnyHashable: Any] {
        [
            RankBuddyUserActivity.Key.collection: FavoriteCollection.interviews.rawValue,
            RankBuddyUserActivity.Key.accountID: accountID.uuidString,
            RankBuddyUserActivity.Key.itemID: interviewID
        ]
    }
}
