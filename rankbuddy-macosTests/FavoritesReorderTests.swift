//
//  FavoritesReorderTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the sidebar Favourites reorder (#41).
@MainActor
struct FavoritesReorderTests {
    private func ref(_ id: String, account: String) -> FavoriteRef {
        FavoriteRef(accountID: account, collection: .tests, itemID: id, title: id)
    }

    @Test func `reordering moves within the account and leaves it well-formed`() {
        let all = [ref("a", account: "A"), ref("b", account: "A"), ref("c", account: "A")]
        // Display order is c, b, a. Move the displayed first item to the end.
        let result = FavoritesReorder.apply(all: all, accountID: "A", from: [0], to: 3)
        #expect(result.map(\.itemID) == ["c", "a", "b"])
        #expect(result.reversed().map(\.itemID) == ["b", "a", "c"])
    }

    @Test func `other accounts' favourites are preserved`() {
        let all = [
            ref("a", account: "A"), ref("b", account: "A"),
            ref("x", account: "B")
        ]
        let result = FavoritesReorder.apply(all: all, accountID: "A", from: [0], to: 2)
        // B's favourite remains in its original storage slot; A's displayed slice is reordered.
        #expect(result[2].itemID == "x")
        let accountA = result.filter { $0.accountID == "A" }.map(\.itemID)
        #expect(accountA == ["b", "a"])
    }
}
