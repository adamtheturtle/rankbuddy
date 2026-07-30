//
//  PersonDetailTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

@MainActor
struct PersonDetailTests {
    @Test func `only active users remain lockable`() {
        #expect(UserLockAvailability.canLock(status: "active", activated: true))
        #expect(!UserLockAvailability.canLock(status: "locked", activated: true))
        #expect(!UserLockAvailability.canLock(status: "deactivated", activated: nil))
        #expect(!UserLockAvailability.canLock(status: "active", activated: false))
        #expect(UserLockAvailability.canLock(status: nil, activated: nil))
    }

    @Test func `team labels retain resolved names and fall back per id`() {
        #expect(PersonTeamResolution.labels(
            ids: ["team-1", "team-2"],
            namesByID: ["team-1": "Platform"]
        ) == ["Platform", "team-2"])
    }

    @Test func `team resolution identity includes its account`() {
        let first = PersonTeamResolutionKey(accountID: UUID(), teamIDs: ["team-1"])
        let second = PersonTeamResolutionKey(accountID: UUID(), teamIDs: ["team-1"])
        #expect(first != second)
    }

    @Test func `team resolution stops at a repeated cursor`() {
        var seen: Set<String> = []
        #expect(PersonTeamResolution.unseenCursor("next", seen: &seen) == "next")
        #expect(PersonTeamResolution.unseenCursor("next", seen: &seen) == nil)
        #expect(PersonTeamResolution.unseenCursor(nil, seen: &seen) == nil)
    }

    @Test func `missing role remains distinct from recruiter`() {
        #expect(PersonRoleEditing.selection(for: nil).isEmpty)
        #expect(PersonRoleEditing.selection(for: "recruiter") == "recruiter")
        #expect(PersonRoleEditing.options.first?.0.isEmpty == true)
        #expect(PersonRoleEditing.options.contains { $0.0 == "recruiter" })
    }
}
