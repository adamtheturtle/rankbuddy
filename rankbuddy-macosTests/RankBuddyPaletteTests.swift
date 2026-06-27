//
//  RankBuddyPaletteTests.swift
//  rankbuddy-macosTests
//

import BuddyAppKit
import CommandPaletteKit
@testable import rankbuddy_macos
import SwiftUI
import Testing

/// Covers the RankBuddy half of the CommandPaletteKit palette (#29): the candidate builder
/// and that activating a result routes correctly.
@MainActor
struct RankBuddyPaletteTests {
    /// Holds a section value so a `Binding` can mutate it from a palette result's action.
    private final class SectionBox {
        var value: SidebarSection = .tests
    }

    private func makeBinding(_ box: SectionBox) -> Binding<SidebarSection> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }

    @Test func `static candidates include sections, the settings command, and accounts`() {
        let store = AccountStore.rankBuddy(isTesting: true, seed: [
            Account(label: "Work", token: "t1"),
            Account(label: "EU", token: "t2")
        ])
        let results = RankBuddyPalette.staticCandidates(
            store: store,
            favorites: FavoritesStore(isTesting: true),
            selection: makeBinding(SectionBox()),
            openSettings: {}
        )

        let ids = Set(results.map(\.id))
        #expect(ids.contains("section.tests"))
        #expect(ids.contains("section.questions"))
        #expect(ids.contains("section.interviews"))
        #expect(ids.contains("command.settings"))
        #expect(results.count(where: { $0.category == "Account" }) == 2)
    }

    @Test func `activating a section result selects that section`() throws {
        let box = SectionBox()
        let results = RankBuddyPalette.staticCandidates(
            store: AccountStore.rankBuddy(isTesting: true),
            favorites: FavoritesStore(isTesting: true),
            selection: makeBinding(box),
            openSettings: {}
        )

        let questions = try #require(results.first { $0.id == "section.questions" })
        questions.action()
        #expect(box.value == .questions)
    }

    @Test func `activating the settings command runs the open-settings action`() throws {
        var opened = false
        let results = RankBuddyPalette.staticCandidates(
            store: AccountStore.rankBuddy(isTesting: true),
            favorites: FavoritesStore(isTesting: true),
            selection: makeBinding(SectionBox()),
            openSettings: { opened = true }
        )

        let settings = try #require(results.first { $0.id == "command.settings" })
        settings.action()
        #expect(opened)
    }

    @Test func `the current account's favourites appear and route to their section`() throws {
        let store = AccountStore.rankBuddy(isTesting: true, seed: [Account(label: "Work", token: "t1")])
        let account = try #require(store.currentAccount)
        let favorites = FavoritesStore(isTesting: true)
        favorites.toggle(FavoriteRef(
            accountID: account.id.uuidString,
            collection: .questions,
            itemID: "q42",
            title: "Two Sum"
        ))

        let box = SectionBox()
        let results = RankBuddyPalette.staticCandidates(
            store: store,
            favorites: favorites,
            selection: makeBinding(box),
            openSettings: {}
        )

        let favorite = try #require(results.first { $0.title == "Two Sum" })
        #expect(favorite.category == "Favourite Questions")
        favorite.action()
        #expect(box.value == .questions)
        // Routing writes the per-account selection key the Questions list restores from.
        #expect(UserDefaults.standard.string(forKey: "selection.questions.\(account.id)") == "q42")
    }

    @Test func `favourites contribute nothing when there are none`() {
        let store = AccountStore.rankBuddy(isTesting: true, seed: [Account(label: "Work", token: "t1")])
        let results = RankBuddyPalette.staticCandidates(
            store: store,
            favorites: FavoritesStore(isTesting: true),
            selection: makeBinding(SectionBox()),
            openSettings: {}
        )
        #expect(!results.contains { $0.id.hasPrefix("favorite.") })
    }
}
