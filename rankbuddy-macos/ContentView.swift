//
//  ContentView.swift
//  rankbuddy-macos
//

import BuddyAppKit
import CommandPaletteKit
import SwiftUI
import UniformTypeIdentifiers
import WhatsNewKit

/// The main window's root: a split view with a sidebar of the top-level sections and a
/// detail pane that hosts the selected section's read-only list and detail views.
struct ContentView: View {
    /// The selected section, persisted across launches (#19).
    @AppStorage("selectedSection") private var selection: SidebarSection = .tests
    @Environment(PaletteModel.self) private var palette
    @Environment(OpenLinkModel.self) private var openLink
    @Environment(AccountStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(AccountHealthMonitor.self) private var health
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    /// Reveals the Favourites drop zone only while a favourite-able row is being dragged (#89).
    @State private var dragMonitor = FavoriteDragMonitor.shared
    /// Whether a drag is currently hovering the Favourites drop zone (drives its highlight).
    @State private var isFavoriteDropTargeted = false
    @State private var candidateRouter = CandidateDeepLinkRouter.shared
    private let whatsNewEnvironment = WhatsNewEnvironment(
        versionStore: WhatsNewContent.versionStore(),
        whatsNewCollection: [WhatsNewContent.current]
    )

    var body: some View {
        @Bindable var palette = palette
        @Bindable var openLink = openLink
        @Bindable var favorites = favorites

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
            NavigationStack {
                VStack(spacing: 0) {
                    // The health monitor probes one current account. In merged mode that account is
                    // an invisible implementation detail, so a single-account warning would blame
                    // the All Accounts scope without identifying which credential needs attention.
                    if !store.isMergedView, health.isUnauthorized(store.currentAccountID) {
                        UnauthorizedBanner()
                    }
                    detailView(for: selection)
                }
            }
            .environment(\.listNavigationIsProvided, true)
            // Warm every section's first page in the background so the first visit to a tab is
            // instant rather than a spinner (#102). Skip the visible section because its list is
            // already loading it. Single-account only — merged lists don't cache.
            .task(id: store.currentAccountID) {
                if let account = store.currentAccount, !store.isMergedView {
                    await SectionPrefetch.warm(account: account, excluding: selection)
                }
            }
        }
        // Drop favourites for accounts that have since been removed, so they never leave
        // dangling palette/navigation entries (#25).
        .onAppear {
            favorites.prune(toAccountIDs: Set(store.accounts.map(\.id.uuidString)))
            openCandidateRequest(candidateRouter.request)
        }
        .onChange(of: candidateRouter.request) { _, request in openCandidateRequest(request) }
        .whatsNewSheet()
        .environment(\.whatsNew, whatsNewEnvironment)
        .onChange(of: store.accounts.map(\.id)) {
            favorites.prune(toAccountIDs: Set(store.accounts.map(\.id.uuidString)))
        }
        // Current-account badge scope must follow account switches immediately instead of
        // retaining the preceding account's count until the next background interval. Re-probe
        // token health here too; startup already performs its own initial probe.
        .onChange(of: store.currentAccountID) {
            Task {
                async let liveness: Void = LivenessMonitor.shared.sweep(store: store)
                async let accountHealth: Void = health.check(store: store)
                _ = await (liveness, accountHealth)
            }
        }
        // Continue a Handoff / Spotlight / Siri activity by routing to the item via the same
        // deep-link path favourites and the open intent use (#98).
        .onContinueUserActivity(RankBuddyUserActivity.activityType) { activity in
            RankBuddyUserActivity.restore(activity, store: store)
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
        .alert("Favourites Couldn’t Be Read", isPresented: $favorites.showsRecoveryAlert) {
            Button("Keep Recovery Copy", role: .cancel) {}
            Button("Reset Favourites", role: .destructive) {
                favorites.resetUnreadableData()
            }
        } message: {
            Text(
                "Your existing favourites were preserved and changes are disabled. " +
                    "Reset only if you want to start with an empty list."
            )
        }
    }

    private func openCandidateRequest(_ request: CandidateDeepLinkRouter.Request?) {
        guard let request,
              let accountID = UUID(uuidString: request.accountID),
              store.accounts.contains(where: { $0.id == accountID }) else { return }

        store.showAllAccounts = false
        store.currentAccountID = accountID
        openWindow(
            value: DetailWindowValue.candidate(
                testID: request.testID,
                candidateID: request.candidateID,
                accountID: accountID
            )
        )
        candidateRouter.consume(request)
    }

    /// Favourites in the selected account scope, shown as a sidebar section (#41).
    private var accountFavorites: [FavoriteRef] {
        if store.isMergedView {
            return favorites.favorites(accountIDs: Set(store.accounts.map(\.id).map(\.uuidString)))
        }
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
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(ref.title)
                    if store.isMergedView, let account = store.accounts.first(where: {
                        $0.id.uuidString == ref.accountID
                    }) {
                        Text(account.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            } icon: {
                Image(systemName: ref.collection.systemImage)
                    .accessibilityHidden(true)
            }
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
        // The synchronous `onDrop` result can only truthfully accept a payload that the app's
        // own row-drag lifecycle created. Merely advertising our exported type is insufficient.
        guard dragMonitor.isDragging else { return false }

        let identifier = UTType.rankBuddyFavorite.identifier
        let accepted = providers.filter { $0.hasItemConformingToTypeIdentifier(identifier) }
        guard !accepted.isEmpty else { return false }

        // Await providers sequentially so asynchronous pasteboard loading cannot reorder the
        // user's drag selection.
        Task { @MainActor in
            for provider in accepted {
                guard let data = await loadFavoriteData(provider, identifier: identifier),
                      let ref = FavoritePasteboard.decode(from: data),
                      store.accounts.contains(where: { $0.id.uuidString == ref.accountID })
                else { continue }

                favorites.add(ref, undoManager: undoManager)
            }
        }
        return true
    }

    private func loadFavoriteData(_ provider: NSItemProvider, identifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// Persists a drag-reorder of the current account's favourites.
    private func moveFavorites(from source: IndexSet, to destination: Int) {
        guard !store.isMergedView, let accountID = store.currentAccount?.id.uuidString else { return }

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
        case .templates:
            TemplatesScreen()
        case .people:
            PeopleScreen()
        case .teams:
            TeamsScreen()
        case .candidates:
            AdministrationScreen(destination: .candidates)
        case .auditLogs:
            AdministrationScreen(destination: .audit)
        case .atsInvitations:
            AdministrationScreen(destination: .ats)
        case .provisioning:
            AdministrationScreen(destination: .provisioning)
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
