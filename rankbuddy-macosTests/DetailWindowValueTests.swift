//
//  DetailWindowValueTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the open-in-new-window value (#49): it round-trips through Codable (so it can
/// pass through openWindow) and titles the window.
@MainActor
struct DetailWindowValueTests {
    private func test(name: String) throws -> HackerRankKit.Test {
        try JSONDecoder().decode(HackerRankKit.Test.self, from: Data(#"{"id":"t1","name":"\#(name)"}"#.utf8))
    }

    @Test func `it round-trips through Codable`() throws {
        let value = try DetailWindowValue.test(test(name: "Backend Screen"), accountID: nil)
        let data = try JSONEncoder().encode(value)
        let restored = try JSONDecoder().decode(DetailWindowValue.self, from: data)
        #expect(restored == value)
    }

    @Test func `the window title comes from the item`() throws {
        #expect(try DetailWindowValue.test(test(name: "Backend Screen"), accountID: nil).windowTitle
            == "Backend Screen")
    }

    @Test func `removed explicit account does not fall back to current account`() {
        let current = Account(label: "Current", token: "token")
        #expect(DetailWindowAccountResolution.resolve(
            id: UUID(),
            accounts: [current],
            current: current
        ) == nil)
        #expect(DetailWindowAccountResolution.resolve(
            id: nil,
            accounts: [current],
            current: current
        )?.id == current.id)
    }
}
