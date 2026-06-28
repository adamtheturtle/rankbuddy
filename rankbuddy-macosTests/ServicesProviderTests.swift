//
//  ServicesProviderTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

/// Coverage for the "Open in RankBuddy" Service's URL resolution (#46).
@MainActor
struct ServicesProviderTests {
    @Test func `a recognised URL resolves against the current account`() {
        let target = ServicesProvider.target(for: "https://www.hackerrank.com/x/tests/t1", currentAccountID: "ACC")
        #expect(target?.collection == .tests)
        #expect(target?.accountID == "ACC")
        #expect(target?.itemID == "t1")
    }

    @Test func `it resolves to nil without an account or without a recognised URL`() {
        // No current account.
        #expect(ServicesProvider.target(for: "https://host/x/tests/t1", currentAccountID: nil) == nil)
        // A bare id can't be typed without the chooser, so the Service ignores it.
        #expect(ServicesProvider.target(for: "bare-id", currentAccountID: "ACC") == nil)
    }
}
