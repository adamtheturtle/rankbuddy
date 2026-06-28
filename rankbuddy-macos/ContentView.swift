//
//  ContentView.swift
//  rankbuddy-macos
//

import AppKit
import BuddyAppKit
import CommandPaletteKit
import SwiftUI

/// The main window's root: a split view with a sidebar of the top-level sections and a
/// detail pane that hosts the selected section's read-only list and detail views.
struct ContentView: View {
    /// The selected section, persisted across launches (#19).
    @AppStorage("selectedSection") private var selection: SidebarSection = .tests
    /// The last app version whose "What's New" was shown (#47).
    @AppStorage(WhatsNew.lastSeenKey) private var lastSeenVersion = ""
    @State private var showWhatsNew = false
    @Environment(PaletteModel.self) private var palette
    @Environment(OpenLinkModel.self) private var openLink
    @Environment(AccountStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(InterviewTemplatesStore.self) private var templates
    @Environment(InterviewTemplateLauncher.self) private var launcher
    @Environment(AccountHealthMonitor.self) private var health

    var body: some View {
        @Bindable var palette = palette
        @Bindable var openLink = openLink

        NavigationSplitView {
            List(selection: sectionSelection) {
                Section {
                    ForEach(SidebarSection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }

                let favourites = accountFavorites
                if !favourites.isEmpty {
                    Section("Favourites") {
                        ForEach(favourites) { ref in
                            Button { openFavorite(ref) } label: {
                                Label(ref.title, systemImage: ref.collection.systemImage)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Remove from Favourites", role: .destructive) {
                                    _ = favorites.toggle(ref)
                                }
                            }
                        }
                        .onMove(perform: moveFavorites)
                    }
                }
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
        .onAppear {
            favorites.prune(toAccountIDs: Set(store.accounts.map(\.id.uuidString)))
            showWhatsNew = WhatsNew.shouldShow(
                currentVersion: WhatsNew.currentVersion, lastSeenVersion: lastSeenVersion
            )
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView { lastSeenVersion = WhatsNew.currentVersion }
        }
        .sheet(isPresented: $openLink.isPresented) {
            OpenLinkSheet().environment(store)
        }
        .sheet(isPresented: $palette.isPresented) {
            CommandPaletteView(placeholder: "Search RankBuddy…") {
                await RankBuddyPalette.candidates(
                    store: store,
                    favorites: favorites,
                    templates: InterviewTemplatePalette(store: templates, launcher: launcher),
                    selection: $selection,
                    openSettings: { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
                )
            }
        }
    }

    /// The current account's favourites, shown as a sidebar section (#41).
    private var accountFavorites: [FavoriteRef] {
        guard let accountID = store.currentAccount?.id.uuidString else { return [] }

        return favorites.favorites(accountID: accountID)
    }

    /// Opens a favourited item: switches to its section and deep-links its detail.
    private func openFavorite(_ ref: FavoriteRef) {
        RankBuddyDeepLink.open(collection: ref.collection, accountID: ref.accountID, itemID: ref.itemID)
        selection = ref.collection.section
    }

    /// Persists a drag-reorder of the current account's favourites.
    private func moveFavorites(from source: IndexSet, to destination: Int) {
        guard let accountID = store.currentAccount?.id.uuidString else { return }

        favorites.replace(with: FavoritesReorder.apply(
            all: favorites.favorites, accountID: accountID, from: source, to: destination
        ))
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
    let favorites = FavoritesStore(isTesting: true)
    favorites.replace(with: [
        FavoriteRef(accountID: Account.demo.id.uuidString, collection: .tests, itemID: "t1", title: "Backend Screen"),
        FavoriteRef(accountID: Account.demo.id.uuidString, collection: .questions, itemID: "q1", title: "Two Sum")
    ])
    return ContentView()
        .environment(AccountStore.rankBuddy(isTesting: true, seed: [.demo]))
        .environment(PaletteModel())
        .environment(OpenLinkModel())
        .environment(favorites)
        .environment(InterviewTemplatesStore(isTesting: true))
        .environment(InterviewTemplateLauncher())
        .environment(AccountHealthMonitor())
}
