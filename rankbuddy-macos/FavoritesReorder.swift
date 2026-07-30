//
//  FavoritesReorder.swift
//  rankbuddy-macos
//

import SwiftUI

/// Pure reordering for the sidebar Favourites section (#41): moves items within one account's
/// favourites while leaving every other account's order untouched. Kept apart from the view so
/// the index maths is unit-testable.
enum FavoritesReorder {
    /// Applies a drag-reorder whose offsets use the newest-first sidebar order, then maps that
    /// order back into the oldest-first stored array without moving other accounts' slots.
    static func apply(
        all: [FavoriteRef],
        accountID: String,
        from source: IndexSet,
        to destination: Int
    ) -> [FavoriteRef] {
        var displayed = Array(all.filter { $0.accountID == accountID }.reversed())
        displayed.move(fromOffsets: source, toOffset: destination)
        var reordered = Array(displayed.reversed()).makeIterator()
        return all.map { favorite in
            favorite.accountID == accountID ? (reordered.next() ?? favorite) : favorite
        }
    }
}
