//
//  CommandPalette.swift
//  rankbuddy-macos
//

import AppKit
import BuddyAppKit
import CommandPaletteKit
import HackerRankKit
import SwiftUI

/// Shared state for the command palette, toggled from the menu/keyboard and observed by
/// `ContentView`, which presents the palette sheet.
@Observable
@MainActor
final class PaletteModel {
    var isPresented = false
}

/// Builds the RankBuddy half of the ⌘K palette (#29): the app-specific candidates that the
/// shared `CommandPaletteKit` package renders, ranks, and navigates. Only `CommandPaletteKit`
/// and RankBuddy's own models are used — no CoderPad/PadBuddy types.
enum RankBuddyPalette {
    /// Candidates available without a network round-trip: the sidebar sections, the
    /// configured accounts, and app commands. Section and command rows show on the empty
    /// query; accounts are search-only so they don't crowd the default list.
    @MainActor
    static func staticCandidates(
        store: AccountStore,
        favorites: FavoritesStore,
        selection: Binding<SidebarSection>,
        openSettings: @escaping @MainActor () -> Void
    ) -> [PaletteResult] {
        var results: [PaletteResult] = []

        for section in SidebarSection.allCases {
            results.append(PaletteResult(
                id: "section.\(section.id)",
                title: section.title,
                category: "Section",
                systemImage: section.systemImage,
                searchText: "\(section.title) section"
            ) { selection.wrappedValue = section })
        }

        // The current account's favourites (shown at rest); contributes nothing — no empty
        // group — when there are none (#25).
        if let account = store.currentAccount {
            results.append(contentsOf: favoriteCandidates(
                account: account, favorites: favorites, selection: selection
            ))
        }

        results.append(PaletteResult(
            id: "command.settings",
            title: "Open Settings",
            category: "Command",
            systemImage: "gearshape",
            searchText: "Open Settings preferences accounts"
        ) { openSettings() })

        for account in store.accounts {
            let isCurrent = account.id == store.currentAccountID
            results.append(PaletteResult(
                id: "account.\(account.id)",
                title: account.label,
                subtitle: isCurrent ? "Current account" : account.baseURL.host(),
                category: "Account",
                systemImage: "person.crop.circle",
                searchText: "\(account.label) account \(account.baseURL.host() ?? "")",
                showsOnlyWhenSearching: true
            ) {
                store.showAllAccounts = false
                store.currentAccountID = account.id
            })
        }

        return results
    }

    /// The current account's favourites as palette results, routed by writing the same
    /// per-account selection key the list restores from, then switching to that section (#25).
    @MainActor
    private static func favoriteCandidates(
        account: Account,
        favorites: FavoritesStore,
        selection: Binding<SidebarSection>
    ) -> [PaletteResult] {
        favorites.favorites(accountID: account.id.uuidString).map { favorite in
            PaletteResult(
                id: "favorite.\(favorite.id)",
                title: favorite.title,
                category: favorite.collection.paletteCategory,
                systemImage: "star.fill",
                searchText: "\(favorite.title) favourite \(favorite.collection.section.title)"
            ) {
                RankBuddyDeepLink.open(
                    collection: favorite.collection,
                    accountID: favorite.accountID,
                    itemID: favorite.itemID
                )
                selection.wrappedValue = favorite.collection.section
            }
        }
    }

    /// The current account's tests, loaded from the API and routed to open in the Tests
    /// section. Search-only so they don't flood the empty palette, and tolerant of load
    /// failure (an offline or token-less account simply contributes no test rows).
    @MainActor
    static func testCandidates(
        store: AccountStore,
        selection: Binding<SidebarSection>
    ) async -> [PaletteResult] {
        guard let account = store.currentAccount,
              let page = try? await HackerRankClient(account: account).testsPage()
        else { return [] }

        return page.items.map { test in
            PaletteResult(
                id: "test.\(test.id)",
                title: test.name,
                subtitle: DisplayFormat.enumLabel(test.state),
                category: "Test",
                systemImage: "checklist",
                searchText: "\(test.name) \(test.tags?.joined(separator: " ") ?? "") test",
                showsOnlyWhenSearching: true
            ) {
                RankBuddyDeepLink.open(
                    collection: .tests,
                    accountID: account.id.uuidString,
                    itemID: test.id
                )
                selection.wrappedValue = .tests
            }
        }
    }

    @MainActor
    static func questionCandidates(
        store: AccountStore,
        selection: Binding<SidebarSection>
    ) async -> [PaletteResult] {
        guard let account = store.currentAccount,
              let page = try? await HackerRankClient(account: account).questionsPage()
        else { return [] }

        return page.items.map { question in
            PaletteResult(
                id: "question.\(question.id)",
                title: question.name,
                subtitle: DisplayFormat.enumLabel(question.type),
                category: "Question",
                systemImage: "questionmark.circle",
                searchText: "\(question.name) \(question.tags?.joined(separator: " ") ?? "") question",
                showsOnlyWhenSearching: true
            ) {
                RankBuddyDeepLink.open(
                    collection: .questions,
                    accountID: account.id.uuidString,
                    itemID: question.id
                )
                selection.wrappedValue = .questions
            }
        }
    }

    @MainActor
    static func interviewCandidates(
        store: AccountStore,
        selection: Binding<SidebarSection>
    ) async -> [PaletteResult] {
        guard let account = store.currentAccount,
              let page = try? await HackerRankClient(account: account).interviewsPage()
        else { return [] }

        return page.items.map { interview in
            let title = interview.title ?? "Interview \(interview.id)"
            return PaletteResult(
                id: "interview.\(interview.id)",
                title: title,
                subtitle: DisplayFormat.enumLabel(interview.status),
                category: "Interview",
                systemImage: "person.2.wave.2",
                searchText: "\(title) \(interview.status) interview",
                showsOnlyWhenSearching: true
            ) {
                RankBuddyDeepLink.open(
                    collection: .interviews,
                    accountID: account.id.uuidString,
                    itemID: interview.id
                )
                selection.wrappedValue = .interviews
            }
        }
    }

    /// Every candidate for the current state: static entries plus the account's primary objects.
    @MainActor
    static func candidates(
        store: AccountStore,
        favorites: FavoritesStore,
        selection: Binding<SidebarSection>,
        openSettings: @escaping @MainActor () -> Void
    ) async -> [PaletteResult] {
        var results = staticCandidates(
            store: store,
            favorites: favorites,
            selection: selection,
            openSettings: openSettings
        )
        await results.append(contentsOf: testCandidates(store: store, selection: selection))
        await results.append(contentsOf: questionCandidates(store: store, selection: selection))
        await results.append(contentsOf: interviewCandidates(store: store, selection: selection))
        return results
    }
}

/// App menu commands: jump to a section (⌘1/⌘2/⌘3) and open the command palette (⌘K).
struct AppCommands: Commands {
    @AppStorage("selectedSection") private var selection: SidebarSection = .tests
    /// The shared detail-pane visibility (#53), toggled by the View ▸ Hide Detail Pane command
    /// (⌃⌘D) — the primary control for the pane, mirroring PadBuddy. The toolbar button that also
    /// flips it is hidden from the default toolbar.
    @AppStorage(ListLayout.detailPaneHiddenKey) private var detailPaneHidden = false
    @Environment(\.openWindow) private var openWindow
    let palette: PaletteModel
    let openLink: OpenLinkModel
    let commandContext: AppCommandContext

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About RankBuddy") { AboutPanel.show() }
        }

        CommandGroup(after: .newItem) {
            Button("Open by URL…") { openLink.isPresented = true }
                .keyboardShortcut("o", modifiers: .command)

            Divider()

            if let primaryNew = commandContext.primaryNew {
                CommandActionButton(action: primaryNew, fallbackTitle: "New RankBuddy Item…")
            } else {
                CommandActionButton(action: nil, fallbackTitle: "New RankBuddy Item…")
            }

            if let secondaryNew = commandContext.secondaryNew {
                CommandActionButton(action: secondaryNew, fallbackTitle: "New RankBuddy Item…")
            }
        }

        CommandGroup(after: .saveItem) {
            CommandActionButton(action: commandContext.exportCSV, fallbackTitle: "Export CSV…")
            CommandActionButton(action: commandContext.exportSelectedCSV, fallbackTitle: "Export Selected CSV…")
            CommandActionButton(action: commandContext.exportMarkdown, fallbackTitle: "Export as Markdown…")
        }

        CommandGroup(replacing: .printItem) {
            CommandActionButton(action: commandContext.print, fallbackTitle: "Print…")
                .keyboardShortcut("p", modifiers: .command)
        }

        // View ▸ Hide/Show Detail Pane (⌃⌘D): the primary control for the persistent detail pane
        // (#53), mirroring PadBuddy. The matching toolbar button is hidden from the default toolbar.
        CommandGroup(after: .sidebar) {
            Button(detailPaneHidden ? "Show Detail Pane" : "Hide Detail Pane") {
                detailPaneHidden.toggle()
            }
            .keyboardShortcut("d", modifiers: [.command, .control])
        }

        CommandMenu("Go") {
            ForEach(Array(SidebarSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { selection = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }

            Divider()

            CommandActionButton(action: commandContext.refresh, fallbackTitle: "Reload")
                .keyboardShortcut("r", modifiers: .command)

            Divider()

            // The account activity feed now lives in its own window, not Settings (#115).
            Button("Account Activity") { openWindow(id: WindowID.activity) }

            Button("Command Palette…") { palette.isPresented = true }
                .keyboardShortcut("k", modifiers: .command)
        }
    }
}
