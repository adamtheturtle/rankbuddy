//
//  RankBuddyPaletteTests.swift
//  rankbuddy-macosTests
//

import BuddyAppKit
import CommandPaletteKit
import HackerRankKit
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

    /// Builds the static candidates, keeping tests focused on the surfaces they assert on.
    private func staticCandidates(
        store: AccountStore,
        favorites: FavoritesStore,
        selection: Binding<SidebarSection>,
        openSettings: @escaping @MainActor () -> Void = {}
    ) -> [PaletteResult] {
        RankBuddyPalette.staticCandidates(
            store: store,
            favorites: favorites,
            selection: selection,
            openSettings: openSettings
        )
    }

    @Test func `static candidates include sections, the settings command, and accounts`() {
        let store = AccountStore.rankBuddy(isTesting: true, seed: [
            Account(label: "Work", token: "t1"),
            Account(label: "EU", token: "t2")
        ])
        let results = staticCandidates(
            store: store,
            favorites: FavoritesStore(isTesting: true),
            selection: makeBinding(SectionBox())
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
        let results = staticCandidates(
            store: AccountStore.rankBuddy(isTesting: true),
            favorites: FavoritesStore(isTesting: true),
            selection: makeBinding(box)
        )

        let questions = try #require(results.first { $0.id == "section.questions" })
        questions.action()
        #expect(box.value == .questions)
    }

    @Test func `activating the settings command runs the open-settings action`() throws {
        var opened = false
        let results = staticCandidates(
            store: AccountStore.rankBuddy(isTesting: true),
            favorites: FavoritesStore(isTesting: true),
            selection: makeBinding(SectionBox()),
            openSettings: { opened = true }
        )

        let settings = try #require(results.first { $0.id == "command.settings" })
        settings.action()
        #expect(opened)
    }

    @Test func `activating an account exits all-accounts mode`() throws {
        let first = Account(label: "Work", token: "t1")
        let second = Account(label: "EU", token: "t2")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [first, second])
        store.showAllAccounts = true
        let results = staticCandidates(
            store: store,
            favorites: FavoritesStore(isTesting: true),
            selection: makeBinding(SectionBox())
        )

        let account = try #require(results.first { $0.id == "account.\(second.id)" })
        account.action()

        #expect(!store.showAllAccounts)
        #expect(store.currentAccountID == second.id)
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
        let results = staticCandidates(
            store: store,
            favorites: favorites,
            selection: makeBinding(box)
        )

        let favorite = try #require(results.first { $0.title == "Two Sum" })
        #expect(favorite.category == "Favourite Questions")
        favorite.action()
        #expect(box.value == .questions)
        // Routing writes the per-account selection key the Questions list restores from.
        #expect(UserDefaults.standard.string(forKey: "selection.questions.\(account.id)") == "q42")
        // The live request reaches a Questions list that was already mounted.
        #expect(DeepLinkRouter.shared.request?.key == "selection.questions.\(account.id)")
        #expect(DeepLinkRouter.shared.request?.itemID == "q42")
    }

    @Test func `favourites contribute nothing when there are none`() {
        let store = AccountStore.rankBuddy(isTesting: true, seed: [Account(label: "Work", token: "t1")])
        let results = staticCandidates(
            store: store,
            favorites: FavoritesStore(isTesting: true),
            selection: makeBinding(SectionBox())
        )
        #expect(!results.contains { $0.id.hasPrefix("favorite.") })
    }

    @Test func `palette discovery follows cursors to its bound`() async throws {
        let items = try await RankBuddyPalette.discoverItems(pageCap: 3) { cursor in
            switch cursor {
            case nil: Page(items: [1], next: "page-2")
            case "page-2": Page(items: [2], next: "page-3")
            default: Page(items: [3], next: "page-4")
            }
        }

        #expect(items == [1, 2, 3])
    }
}
