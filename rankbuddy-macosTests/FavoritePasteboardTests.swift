//
//  FavoritePasteboardTests.swift
//  rankbuddy-macosTests
//

import AppKit
import Foundation
@testable import rankbuddy_macos
import Testing
import UniformTypeIdentifiers

/// The pure drag payload behind drag-to-pin (#89): a list row encodes its `FavoriteRef` onto
/// the pasteboard and the sidebar drop target decodes it back. The round-trip is what carries
/// the dragged item — account and all — from the list to Favourites, so it's worth pinning down.
struct FavoritePasteboardTests {
    private func ref() -> FavoriteRef {
        FavoriteRef(accountID: "acc1", collection: .interviews, itemID: "i7", title: "Senior Pairing")
    }

    @Test func `a pasteboard item round-trips a favourite ref`() throws {
        let item = try #require(FavoritePasteboard.item(for: ref()))
        let data = try #require(
            item.data(forType: NSPasteboard.PasteboardType(UTType.rankBuddyFavorite.identifier))
        )
        #expect(FavoritePasteboard.decode(from: data) == ref())
    }

    @Test func `the pasteboard item carries the exported favourite type`() throws {
        let item = try #require(FavoritePasteboard.item(for: ref()))
        #expect(item.types.contains(NSPasteboard.PasteboardType(UTType.rankBuddyFavorite.identifier)))
    }

    @Test func `decoding rejects data that isn't ours`() {
        #expect(FavoritePasteboard.decode(from: Data("not a favourite".utf8)) == nil)
    }

    @Test func `a raw forged favourite ref is rejected`() throws {
        let forged = try JSONEncoder().encode(ref())
        #expect(FavoritePasteboard.decode(from: forged) == nil)
    }
}
