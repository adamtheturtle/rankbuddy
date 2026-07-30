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
}
