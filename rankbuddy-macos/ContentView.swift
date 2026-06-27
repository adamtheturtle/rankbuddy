import AppKit
import BuddyAppKit
import CommandPaletteKit
import SwiftUI

/// The main window's root: a split view with a sidebar of the top-level sections and a
/// detail pane that hosts the selected section's read-only list and detail views.
struct ContentView: View {
    /// The selected section, persisted across launches (#19).
    @AppStorage("selectedSection") private var selection: SidebarSection = .tests
    @Environment(PaletteModel.self) private var palette
    @Environment(AccountStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(AccountHealthMonitor.self) private var health

    var body: some View {
        @Bindable var palette = palette

        NavigationSplitView {
            List(SidebarSection.allCases, selection: sectionSelection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("RankBuddy")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                AccountSwitcher()
            }
        } detail: {
            VStack(spacing: 0) {
                if health.isUnauthorized(store.currentAccountID) {
                    UnauthorizedBanner()
                }
                detailView(for: selection)
            }
            // Re-probe whenever the active account changes, so switching to a revoked
            // account flags it without waiting for the periodic check (#40).
            .task(id: store.currentAccountID) { await health.check(store: store) }
        }
        // Drop favourites for accounts that have since been removed, so they never leave
        // dangling palette/navigation entries (#25).
        .onAppear { favorites.prune(toAccountIDs: Set(store.accounts.map(\.id.uuidString))) }
        .sheet(isPresented: $palette.isPresented) {
            CommandPaletteView(placeholder: "Search RankBuddy…") {
                await RankBuddyPalette.candidates(
                    store: store,
                    favorites: favorites,
                    selection: $selection,
                    openSettings: { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
                )
            }
        }
    }

    /// A `List` selection binding that never clears to nil, so a section is always shown.
    private var sectionSelection: Binding<SidebarSection?> {
        Binding(
            get: { selection },
            set: { selection = $0 ?? selection }
        )
    }

    @ViewBuilder private func detailView(for section: SidebarSection) -> some View {
        switch section {
        case .tests:
            TestsScreen()
        case .questions:
            QuestionsScreen()
        case .interviews:
            InterviewsScreen()
        case .people:
            PeopleScreen()
        case .teams:
            TeamsScreen()
        }
    }
}

#Preview {
    ContentView()
        .environment(AccountStore.rankBuddy(isTesting: true))
        .environment(PaletteModel())
        .environment(FavoritesStore(isTesting: true))
        .environment(AccountHealthMonitor())
}
