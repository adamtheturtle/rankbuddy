//
//  AccountActivity.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

/// A read-only, paged view of the current account's audit log (#106) — the organisation's actual
/// change history from `GET /audit_log` (who changed what, when, from where). Distinct from the
/// local Recent Activity, which only records what this app *viewed*. Loads the first page on
/// appearance (and when the account changes) and pages in more on demand.
struct AccountActivityView: View {
    @Environment(AccountStore.self) private var store

    @State private var selectedAccountID: Account.ID?
    @State private var entries: [AuditLogEntry] = []
    @State private var nextCursor: String?
    @State private var phase: Phase = .loading
    @State private var isLoadingMore = false
    @State private var loadMoreError: String?
    @State private var reloadGeneration = 0
    @State private var loadedCursors: Set<String> = []
    @State private var sourceType = ""
    @State private var dateRange = ""

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    struct PaginationRequest: Equatable {
        let accountID: Account.ID
        let generation: Int
        let cursor: String
    }

    var body: some View {
        if let account = activityAccount {
            VStack(spacing: 0) {
                accountPicker(selectedAccount: account)
                AccountActivityFilters(sourceType: $sourceType, dateRange: $dateRange,
                                       isLoading: phase == .loading || isLoadingMore) {
                    Task { await reload(account: account) }
                }
                Divider()
                stateView(account: account)
            }
            .task(id: account.id) { await reload(account: account) }
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { await reload(account: account) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh Account Activity")
                    .disabled(phase == .loading)
                }
            }
            .focusedSceneValue(
                \.accountActivityRefresh,
                AccountActivityRefreshAction(isEnabled: phase != .loading) {
                    Task { await reload(account: account) }
                }
            )
        } else {
            ContentUnavailableView(
                "No Account",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Add an account to see its activity.")
            )
        }
    }

    private var activityAccount: Account? {
        if let selectedAccountID,
           let selected = store.accounts.first(where: { $0.id == selectedAccountID }) {
            return selected
        }
        return store.currentAccount ?? store.accounts.first
    }

    private func accountPicker(selectedAccount: Account) -> some View {
        HStack {
            Label("Showing activity for", systemImage: selectedAccount.displayIcon)
                .foregroundStyle(.secondary)
            Picker(
                "Account",
                selection: Binding(
                    get: { selectedAccount.id },
                    set: { selectedAccountID = $0 }
                )
            ) {
                ForEach(store.accounts) { account in
                    Text(account.label).tag(account.id)
                }
            }
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func stateView(account: Account) -> some View {
        switch phase {
        case .loading:
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded where entries.isEmpty:
            ContentUnavailableView(
                "No Activity",
                systemImage: "clock.arrow.circlepath",
                description: Text("No recent changes are recorded for this account.")
            )

        case .loaded:
            List {
                ForEach(entries) { entry in
                    AuditLogRow(entry: entry)
                }
                if nextCursor != nil {
                    loadMoreRow(account: account)
                }
            }

        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn’t load activity", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await reload(account: account) } }
            }
        }
    }

    private func loadMoreRow(account: Account) -> some View {
        VStack(spacing: 6) {
            if isLoadingMore {
                ProgressView().controlSize(.small)
            } else {
                Button("Load More") { Task { await loadMore(account: account) } }
                    .buttonStyle(.borderless)
            }
            if let loadMoreError {
                Label(loadMoreError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Couldn’t load more activity: \(loadMoreError)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func reload(account: Account) async {
        reloadGeneration += 1
        let generation = reloadGeneration
        phase = .loading
        loadMoreError = nil
        loadedCursors = []
        do {
            let page = try await HackerRankClient(account: account).auditLogCursorPage(filters: AuditLogFilters(
                sourceType: sourceType.isEmpty ? nil : sourceType,
                createdAt: DateRangeFilter.createdAtServerValue(dateRange), sort: "created_at"
            ))
            guard Self.isCurrentRequest(
                accountID: account.id,
                currentAccountID: activityAccount?.id,
                generation: generation,
                currentGeneration: reloadGeneration
            ) else { return }

            entries = Self.mergedEntries([], with: page.data)
            nextCursor = page.nextCursor
            phase = .loaded
        } catch {
            guard Self.isCurrentRequest(
                accountID: account.id,
                currentAccountID: activityAccount?.id,
                generation: generation,
                currentGeneration: reloadGeneration
            ) else { return }

            phase = .failed(error.localizedDescription)
        }
    }

    private func loadMore(account: Account) async {
        guard let cursor = nextCursor, !isLoadingMore else { return }

        let request = PaginationRequest(
            accountID: account.id,
            generation: reloadGeneration,
            cursor: cursor
        )
        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }
        do {
            let page = try await HackerRankClient(account: account).auditLogCursorPage(cursor: cursor)
            guard Self.isCurrentPagination(
                request,
                currentAccountID: activityAccount?.id,
                currentGeneration: reloadGeneration,
                currentCursor: nextCursor
            ) else { return }

            if Self.hasCursorCycle(next: page.nextCursor, requested: cursor, previouslyLoaded: loadedCursors) {
                loadMoreError = "The server repeated an earlier page. Refresh to check again."
                return
            }
            loadedCursors.insert(cursor)
            entries = Self.mergedEntries(entries, with: page.data)
            nextCursor = page.nextCursor
        } catch {
            guard Self.isCurrentPagination(
                request,
                currentAccountID: activityAccount?.id,
                currentGeneration: reloadGeneration,
                currentCursor: nextCursor
            ) else { return }

            loadMoreError = error.localizedDescription
        }
    }

    /// Preserves server order while replacing an existing record when a later page repeats its
    /// stable identity. This keeps SwiftUI's `ForEach` identities unique across page boundaries.
    static func mergedEntries(
        _ existing: [AuditLogEntry],
        with incoming: [AuditLogEntry]
    ) -> [AuditLogEntry] {
        var merged: [AuditLogEntry] = []
        var indexByID: [AuditLogEntry.ID: Int] = [:]
        for entry in existing + incoming {
            if let index = indexByID[entry.id] {
                merged[index] = entry
            } else {
                indexByID[entry.id] = merged.endIndex
                merged.append(entry)
            }
        }
        return merged
    }

    /// A request may publish only while both its account and reload generation are still active.
    /// Task cancellation is cooperative, so this validation remains necessary after every await.
    static func isCurrentRequest(
        accountID: Account.ID,
        currentAccountID: Account.ID?,
        generation: Int,
        currentGeneration: Int
    ) -> Bool {
        accountID == currentAccountID && generation == currentGeneration
    }

    /// Pagination also pins the cursor it started from, so a response cannot append into a list
    /// whose account, reload, or page boundary changed while the request was in flight.
    static func isCurrentPagination(
        _ request: PaginationRequest,
        currentAccountID: Account.ID?,
        currentGeneration: Int,
        currentCursor: String?
    ) -> Bool {
        isCurrentRequest(
            accountID: request.accountID,
            currentAccountID: currentAccountID,
            generation: request.generation,
            currentGeneration: currentGeneration
        ) && request.cursor == currentCursor
    }

    static func hasCursorCycle(next: String?, requested: String, previouslyLoaded: Set<String>) -> Bool {
        next == requested || next.map(previouslyLoaded.contains) == true
    }
}

/// The activity window's scene-local refresh command. A focused value avoids routing Command-R
/// through whichever list happened to register in the separate main window.
struct AccountActivityRefreshAction {
    let isEnabled: Bool
    let perform: @MainActor () -> Void
}

private struct AccountActivityRefreshKey: FocusedValueKey {
    typealias Value = AccountActivityRefreshAction
}

extension FocusedValues {
    var accountActivityRefresh: AccountActivityRefreshAction? {
        get { self[AccountActivityRefreshKey.self] }
        set { self[AccountActivityRefreshKey.self] = newValue }
    }
}

/// One row in the account activity feed (#106): the change summary, who made it, when, and which
/// fields changed.
struct AuditLogRow: View {
    let entry: AuditLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label(entry.headline, systemImage: entry.actionSymbol)
                    .font(.headline)
                Spacer()
                RelativeDateText(iso: entry.createdAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let user = entry.userLabel {
                Text(user)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !entry.modifiedFields.isEmpty {
                Text("Changed: \(entry.modifiedFields.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Activity rows") {
    let json = #"""
    {"data":[
      {"source_id":"t1","source_type":"test","action":"update",
       "user":{"firstname":"Rhea","lastname":"Recruiter","email":"rhea@example.com"},
       "modified_fields":["name","cutoff_score"],"created_at":"2026-06-20T09:15:00Z"},
      {"source_id":1024,"source_type":"interview","action":"delete",
       "user":"ian@example.com","modified_fields":[],"created_at":"2026-06-18T11:05:00Z"}
    ]}
    """#
    let page = try? JSONDecoder().decode(HackerRankPage<AuditLogEntry>.self, from: Data(json.utf8))
    return VStack(alignment: .leading, spacing: 10) {
        ForEach(page?.data ?? []) { entry in
            AuditLogRow(entry: entry)
            Divider()
        }
    }
    .padding()
    .frame(width: 480)
}

private struct AccountActivityFilters: View {
    @Binding var sourceType: String
    @Binding var dateRange: String
    let isLoading: Bool
    let apply: () -> Void

    var body: some View {
        HStack {
            Picker("Changed object", selection: $sourceType) {
                Text("All objects").tag("")
                ForEach(["test", "question", "interview", "user", "team", "test_candidate"], id: \.self) {
                    Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0)
                }
            }
            Picker("Date", selection: $dateRange) {
                Text("All dates").tag("")
                ForEach(NamedDateRange.options, id: \.self) { Text($0).tag($0) }
            }
            Button("Apply", action: apply).disabled(isLoading)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
