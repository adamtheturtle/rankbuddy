//
//  LivenessDigestTests.swift
//  rankbuddy-macosTests
//

import BuddyAppKit
import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the pure liveness derivations (#32): the scheduled-interview count and the
/// Dock badge label behind the background-updates feature.
@MainActor
struct LivenessDigestTests {
    private func interview(id: String, status: String) throws -> Interview {
        let json = #"{"id":"\#(id)","status":"\#(status)","url":"https://example.com/x"}"#
        return try JSONDecoder().decode(Interview.self, from: Data(json.utf8))
    }

    @Test func `scheduled count uses every normalized actionable status`() throws {
        let interviews = try [
            interview(id: "1", status: "scheduled"),
            interview(id: "2", status: " Upcoming "),
            interview(id: "3", status: "LIVE"),
            interview(id: "4", status: "in_progress"),
            interview(id: "5", status: "in-progress"),
            interview(id: "6", status: "ongoing"),
            interview(id: "7", status: "completed"),
            interview(id: "8", status: "cancelled")
        ]
        #expect(LivenessDigest.scheduledCount(interviews) == 6)
    }

    @Test func `an empty list has no scheduled interviews`() {
        #expect(LivenessDigest.scheduledCount([]) == 0)
    }

    @Test func `the badge label is nil at zero and the number otherwise`() {
        #expect(LivenessDigest.badgeLabel(scheduledCount: 0) == nil)
        #expect(LivenessDigest.badgeLabel(scheduledCount: 1) == "1")
        #expect(LivenessDigest.badgeLabel(scheduledCount: 12) == "12")
    }

    @Test func `a badge total requires a last-known count for every scoped account`() throws {
        let first = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let second = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))

        #expect(LivenessDigest.scheduledTotal(accountIDs: [first, second], lastKnown: [first: 3]) == nil)
        #expect(
            LivenessDigest.scheduledTotal(accountIDs: [first, second], lastKnown: [first: 3, second: 2]) == 5
        )
    }

    @Test func `new interviews are those not in the previous set`() throws {
        let current = try [
            interview(id: "a", status: "scheduled"),
            interview(id: "b", status: "scheduled"),
            interview(id: "c", status: "completed")
        ]
        let new = LivenessDigest.newInterviews(previousIDs: ["a"], current: current)
        #expect(new.map(\.id) == ["b"])
        // Nothing new when every id was already seen.
        #expect(LivenessDigest.newInterviews(previousIDs: ["a", "b", "c"], current: current).isEmpty)
    }

    @Test func `notifications include actionable statuses and reject terminal ones`() {
        for status in ["scheduled", " Upcoming ", "LIVE", "in_progress", "in-progress", "ongoing"] {
            #expect(LivenessDigest.isNotificationEligible(status: status))
        }
        for status in ["completed", "cancelled", "archived", "expired", ""] {
            #expect(!LivenessDigest.isNotificationEligible(status: status))
        }
    }

    @Test func `the notification body singularises one interview`() {
        #expect(LivenessDigest.notificationBody(newCount: 1) == "1 new interview")
        #expect(LivenessDigest.notificationBody(newCount: 3) == "3 new interviews")
    }

    @Test func `notification routing preserves the source account and interview`() throws {
        let accountID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let userInfo = LivenessNotifier.notificationUserInfo(accountID: accountID, interviewID: "interview-7")
        let target = try #require(RankBuddyUserActivity.target(userInfo: userInfo))

        #expect(target.collection == .interviews)
        #expect(target.accountID == accountID.uuidString)
        #expect(target.itemID == "interview-7")
    }

    @Test func `notification identifiers coalesce only within an account`() {
        let accountA = UUID()
        let accountB = UUID()
        let first = LivenessNotifier.notificationID(accountID: accountA)
        let repeated = LivenessNotifier.notificationID(accountID: accountA)

        #expect(first == repeated)
        #expect(first != LivenessNotifier.notificationID(accountID: accountB))
    }

    @Test func `the refresh cadence clamps unset and unknown values to the default`() {
        // Unset (0) and out-of-range values fall back to the default; supported options pass.
        #expect(LivenessSettings.intervalMinutes(raw: 0) == LivenessSettings.defaultIntervalMinutes)
        #expect(LivenessSettings.intervalMinutes(raw: 7) == LivenessSettings.defaultIntervalMinutes)
        #expect(LivenessSettings.intervalMinutes(raw: 10) == 10)
    }

    @Test func `clearing seen interviews removes only the selected account history`() throws {
        let suite = "liveness-seen-\(#function)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let accountA = UUID()
        let accountB = UUID()
        defaults.set(Data("a".utf8), forKey: LivenessSettings.seenKey(accountA))
        defaults.set(Data("b".utf8), forKey: LivenessSettings.seenKey(accountB))

        LivenessSettings.clearSeen(accountID: accountA, defaults: defaults)

        #expect(defaults.object(forKey: LivenessSettings.seenKey(accountA)) == nil)
        #expect(defaults.data(forKey: LivenessSettings.seenKey(accountB)) == Data("b".utf8))
    }

    @MainActor
    @Test func `the dock badge scope picks the right accounts and always excludes the demo`() {
        let real = Account(label: "Work", token: "tok-1")
        let other = Account(label: "EU", token: "tok-2")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [real, other, .demo])

        // "Current account" badges only the selected (first-seeded) real account.
        let current = DockBadgeScope.currentAccount.badgeableAccounts(in: store)
        #expect(current.count == 1)
        #expect(current.allSatisfy { !$0.isMock })

        // "All accounts" badges both real accounts but never the demo.
        let all = DockBadgeScope.allAccounts.badgeableAccounts(in: store)
        #expect(all.count == 2)
        #expect(all.allSatisfy { !$0.isMock })

        // Merged mode has no visible current account, so current scope follows the visible set.
        store.showAllAccounts = true
        let merged = DockBadgeScope.currentAccount.badgeableAccounts(in: store)
        #expect(merged.count == 2)
        #expect(merged.allSatisfy { !$0.isMock })
    }

    @Test func `probe scheduler bounds concurrency and yields every healthy result`() async {
        actor Tracker {
            var active = 0
            var maximum = 0

            func begin() {
                active += 1
                maximum = max(maximum, active)
            }

            func end() {
                active -= 1
            }
        }

        let tracker = Tracker()
        var received: [Int] = []
        await LivenessProbe.forEachResult(
            Array(0 ..< 8),
            limit: 2,
            operation: { value in
                await tracker.begin()
                try? await Task.sleep(for: .milliseconds(5))
                await tracker.end()
                return value
            },
            onResult: { received.append($0) }
        )

        #expect(await tracker.maximum == 2)
        #expect(Set(received) == Set(0 ..< 8))
    }

    @Test func `probe timeout does not await losing work`() async {
        let clock = ContinuousClock()
        let start = clock.now

        let result: Int? = await LivenessProbe.firstResult(timeout: .milliseconds(5)) {
            try? await Task.sleep(for: .seconds(2))
            return 1
        }

        #expect(result == nil)
        #expect(start.duration(to: clock.now) < .milliseconds(500))
    }

    @Test func `liveness probe follows interview cursors`() async throws {
        let first = try interview(id: "first", status: "completed")
        let second = try interview(id: "second", status: "scheduled")

        let interviews = try await LivenessProbe.pagedInterviews(limit: 5) { cursor in
            switch cursor {
            case nil: Page(items: [first], next: "page-two")
            case "page-two": Page(items: [second], next: nil)
            default: Page(items: [], next: nil)
            }
        }

        #expect(interviews.map(\.id) == ["first", "second"])
    }
}
