//
//  DetailFavoriteButton.swift
//  rankbuddy-macos
//

import SwiftUI

/// The same account-scoped favourite as the list star, also available in standalone windows.
struct DetailFavoriteButton: View {
    let reference: FavoriteRef?
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.undoManager) private var undoManager

    private var isFavorite: Bool {
        guard let reference else { return false }

        return favorites.isFavorite(collection: reference.collection, accountID: reference.accountID,
                                    itemID: reference.itemID)
    }

    private var title: String {
        isFavorite ? "Remove from Favourites" : "Add to Favourites"
    }

    var body: some View {
        Button {
            guard let reference else { return }

            favorites.toggle(reference, undoManager: undoManager)
        } label: {
            Label(title, systemImage: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? Color.yellow : Color.primary)
        }
        .help(title)
        .accessibilityLabel(title)
        .disabled(reference == nil || favorites.hasUnreadableData)
    }
}
