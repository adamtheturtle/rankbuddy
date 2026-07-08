//
//  RowTransferTests.swift
//  rankbuddy-macosTests
//

import AppKit
import Foundation
@testable import rankbuddy_macos
import Testing
import UniformTypeIdentifiers

struct RowTransferTests {
    @Test func `single row exposes readable plain text and tabular text`() {
        let row = RowTransfer(
            title: "Ada Lovelace",
            subtitle: "ada@example.com",
            fields: [("Name", "Ada Lovelace"), ("Email", "ada@example.com")]
        )

        #expect(row.plainText == "Ada Lovelace\nada@example.com")
        #expect(row.tabularText == "Ada Lovelace\tada@example.com")
    }

    @Test func `multi row tabular text is newline separated`() {
        let rows = [
            RowTransfer(title: "One", fields: [("Name", "One"), ("Status", "Active")]),
            RowTransfer(title: "Two", fields: [("Name", "Two"), ("Status", "Archived")])
        ]

        #expect(RowTransfer.tabularText(rows) == "One\tActive\nTwo\tArchived")
    }

    @Test func `tabular fields strip tabs and newlines`() {
        let row = RowTransfer(title: "Name", fields: [("Name", "Ada\tLovelace\nEngineer")])

        #expect(row.tabularText == "Ada Lovelace Engineer")
    }

    @Test func `pasteboard item carries public text URL and private favourite payload`() throws {
        let favorite = FavoriteRef(accountID: "a", collection: .interviews, itemID: "i1", title: "Pairing")
        let row = RowTransfer(title: "Pairing", url: URL(string: "https://example.com/i1"))
        let item = row.pasteboardItem(favoriteRef: favorite)

        #expect(item.string(forType: .string) == "Pairing\nhttps://example.com/i1")
        #expect(item.string(forType: .URL) == "https://example.com/i1")
        let data = try #require(item.data(forType: NSPasteboard.PasteboardType(UTType.rankBuddyFavorite.identifier)))
        #expect(FavoritePasteboard.decode(from: data) == favorite)
    }
}
