//
//  FavoritesReorderTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the sidebar Favourites reorder (#41).
struct FavoritesReorderTests {
    private func ref(_ id: String, account: String) -> FavoriteRef {
        FavoriteRef(accountID: account, collection: .tests, itemID: id, title: id)
    }

    @Test func `reordering moves within the account and leaves it well-formed`() {
        let all = [ref("a", account: "A"), ref("b", account: "A"), ref("c", account: "A")]
        // Move the last item to the front.
        let result = FavoritesReorder.apply(all: all, accountID: "A", from: [2], to: 0)
        #expect(result.map(\.itemID) == ["c", "a", "b"])
    }

    @Test func `other accounts' favourites are preserved`() {
        let all = [
            ref("a", account: "A"), ref("b", account: "A"),
            ref("x", account: "B")
        ]
        let result = FavoritesReorder.apply(all: all, accountID: "A", from: [1], to: 0)
        // B's favourite still present; A's slice reordered.
        #expect(result.contains { $0.itemID == "x" && $0.accountID == "B" })
        let accountA = result.filter { $0.accountID == "A" }.map(\.itemID)
        #expect(accountA == ["b", "a"])
    }
}
