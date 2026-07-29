//
//  ContentView.swift
//  rankbuddy-macos
//

import AppKit
import BuddyAppKit
import CommandPaletteKit
import SwiftUI
import UniformTypeIdentifiers

/// The main window's root: a split view with a sidebar of the top-level sections and a
/// detail pane that hosts the selected section's read-only list and detail views.
struct ContentView: View {
    /// The selected section, persisted across launches (#19).
    @AppStorage("selectedSection") private var selection: SidebarSection = .tests
    /// The last app version/build whose "What's New" was shown (#47).
    @AppStorage(WhatsNew.lastSeenKey) private var lastSeenRelease = ""
    @State private var showWhatsNew = false
    @Environment(PaletteModel.self) private var palette
    @Environment(OpenLinkModel.self) private var openLink
    @Environment(AccountStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(AccountHealthMonitor.self) private var health
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openSettings) private var openSettings
    /// Reveals the Favourites drop zone only while a favourite-able row is being dragged (#89).
    @State private var dragMonitor = FavoriteDragMonitor.shared
    /// Whether a drag is currently hovering the Favourites drop zone (drives its highlight).
    @State private var isFavoriteDropTargeted = false

    var body: some View {
        @Bindable var palette = palette
        @Bindable var openLink = openLink

        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: sectionSelection) {
                    Section {
                        ForEach(SidebarSection.allCases) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(section)
                        }
                    }

                    let favourites = accountFavorites
                    // The section also appears (empty) while a favourite-able row is being dragged,
                    // so there's always somewhere to drop it — the empty-state drop zone of #89.
                    if !favourites.isEmpty || dragMonitor.isDragging {
                        Section("Favourites") {
                            ForEach(favourites) { ref in
                                favoriteRow(ref)
                            }
                            .onMove(perform: moveFavorites)

                            // Revealed only mid-drag (#89): a clear target that also covers the
                            // empty-favourites case, where there's no row to drop onto.
                            if dragMonitor.isDragging {
                                favoriteDropZone
                            }
                        }
                    }
                }
                .listStyle(.sidebar)

                Divider()
                AccountSwitcher()
                    .padding(10)
                    .background(.thinMaterial)
            }
            .navigationTitle("RankBuddy")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
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
            // Warm every section's first page in the background so the first visit to a tab is
            // instant rather than a spinner (#102). Single-account only — merged lists don't cache.
            .task(id: store.currentAccountID) {
                if let account = store.currentAccount, !store.isMergedView {
                    await SectionPrefetch.warm(account: account)
                }
            }
        }
        // Drop favourites for accounts that have since been removed, so they never leave
        // dangling palette/navigation entries (#25).
        .onAppear {
            favorites.prune(toAccountIDs: Set(store.accounts.map(\.id.uuidString)))
            showWhatsNew = WhatsNew.shouldShow(
                currentVersion: WhatsNew.currentVersion,
                currentBuild: WhatsNew.currentBuild,
                lastSeenRelease: lastSeenRelease
            )
        }
        // Continue a Handoff / Spotlight / Siri activity by routing to the item via the same
        // deep-link path favourites and the open intent use (#98).
        .onContinueUserActivity(RankBuddyUserActivity.activityType) { activity in
            RankBuddyUserActivity.restore(activity)
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView { lastSeenRelease = WhatsNew.currentReleaseIdentifier }
        }
        .sheet(isPresented: $openLink.isPresented) {
            OpenLinkSheet().environment(store)
        }
        .sheet(isPresented: $palette.isPresented) {
            CommandPaletteView(placeholder: "Search RankBuddy…") {
                await RankBuddyPalette.candidates(
                    store: store,
                    favorites: favorites,
                    selection: $selection,
                    openSettings: { openSettings() }
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

    /// One favourite row. Opening deep-links it; the context menu removes it; and the row is
    /// itself a drop target, so dropping a dragged list row anywhere over the section pins it (#89).
    private func favoriteRow(_ ref: FavoriteRef) -> some View {
        Button { openFavorite(ref) } label: {
            Label(ref.title, systemImage: ref.collection.systemImage)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove from Favourites", role: .destructive) {
                _ = favorites.toggle(ref, undoManager: undoManager)
            }
        }
        // `.onDrop`, not `.dropDestination(for:)`: the latter never fires its action inside a
        // List row. Dropping onto an existing favourite adds the dragged item (it doesn't reorder).
        .onDrop(of: [.rankBuddyFavorite], isTargeted: nil) { handleFavoriteDrop($0) }
    }

    /// The mid-drag drop zone (#89): a clear hint that also covers the empty-favourites case,
    /// where there's no row to drop onto. Highlights Finder-style while a drag hovers it.
    private var favoriteDropZone: some View {
        Label("Drop to add to Favourites", systemImage: "plus.circle.dashed")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                isFavoriteDropTargeted ? Color.accentColor.opacity(0.15) : .clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .onDrop(of: [.rankBuddyFavorite], isTargeted: $isFavoriteDropTargeted) { handleFavoriteDrop($0) }
    }

    /// Pins each dropped item to the account carried in its payload (so a drop pins to the
    /// originating account, not whichever happens to be active). Returns whether anything ours
    /// was accepted, which drives the drop animation.
    private func handleFavoriteDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        let identifier = UTType.rankBuddyFavorite.identifier
        for provider in providers where provider.hasItemConformingToTypeIdentifier(identifier) {
            accepted = true
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                guard let data, let ref = FavoritePasteboard.decode(from: data) else { return }

                Task { @MainActor in favorites.add(ref, undoManager: undoManager) }
            }
        }
        return accepted
    }

    /// Persists a drag-reorder of the current account's favourites.
    private func moveFavorites(from source: IndexSet, to destination: Int) {
        guard let accountID = store.currentAccount?.id.uuidString else { return }

        favorites.replace(
            with: FavoritesReorder.apply(
                all: favorites.favorites, accountID: accountID, from: source, to: destination
            ),
            undoManager: undoManager,
            actionName: "Reorder Favourites"
        )
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
        .environment(AccountHealthMonitor())
}
