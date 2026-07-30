//
//  PersonDetailTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

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
}
