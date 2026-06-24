import AppKit
import BuddyAppKit
import CommandPaletteKit
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
            ) { store.currentAccountID = account.id })
        }

        return results
    }

    /// The current account's tests, loaded from the API and routed to open in the Tests
    /// section. Search-only so they don't flood the empty palette, and tolerant of load
    /// failure (an offline or token-less account simply contributes no test rows).
    @MainActor
    static func testCandidates(
        store: AccountStore,
        session: URLSession,
        selection: Binding<SidebarSection>
    ) async -> [PaletteResult] {
        guard let account = store.currentAccount,
              let tests = try? await HackerRankClient(account: account, session: session).tests()
        else { return [] }

        return tests.map { test in
            PaletteResult(
                id: "test.\(test.id)",
                title: test.name,
                subtitle: test.state?.capitalized,
                category: "Test",
                systemImage: "checklist",
                searchText: "\(test.name) \(test.tags?.joined(separator: " ") ?? "") test",
                showsOnlyWhenSearching: true
            ) {
                // Route through the same per-account key the Tests list restores from (#19),
                // then switch to the section so the list opens that test's detail.
                UserDefaults.standard.set(test.id, forKey: "selection.tests.\(account.id)")
                selection.wrappedValue = .tests
            }
        }
    }

    /// Every candidate for the current state: the static entries plus the account's tests.
    @MainActor
    static func candidates(
        store: AccountStore,
        session: URLSession,
        selection: Binding<SidebarSection>,
        openSettings: @escaping @MainActor () -> Void
    ) async -> [PaletteResult] {
        var results = staticCandidates(store: store, selection: selection, openSettings: openSettings)
        await results.append(contentsOf: testCandidates(store: store, session: session, selection: selection))
        return results
    }
}

/// App menu commands: jump to a section (⌘1/⌘2/⌘3) and open the command palette (⌘K).
struct AppCommands: Commands {
    @AppStorage("selectedSection") private var selection: SidebarSection = .tests
    let palette: PaletteModel

    var body: some Commands {
        CommandMenu("Go") {
            ForEach(Array(SidebarSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { selection = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }

            Divider()

            Button("Command Palette…") { palette.isPresented = true }
                .keyboardShortcut("k", modifiers: .command)
        }
    }
}
