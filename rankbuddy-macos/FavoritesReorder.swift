//
//  FavoritesReorder.swift
//  rankbuddy-macos
//

import SwiftUI

/// Pure reordering for the sidebar Favourites section (#41): moves items within one account's
/// favourites while leaving every other account's order untouched. Kept apart from the view so
/// the index maths is unit-testable.
enum FavoritesReorder {
    /// Applies a drag-reorder (`from`/`to` are offsets within the account's own favourites) and
    /// returns the full favourites list with that account's slice reordered.
    static func apply(
        all: [FavoriteRef],
        accountID: String,
        from source: IndexSet,
        to destination: Int
    ) -> [FavoriteRef] {
        var account = all.filter { $0.accountID == accountID }
        account.move(fromOffsets: source, toOffset: destination)
        let others = all.filter { $0.accountID != accountID }
        return others + account
    }
}
