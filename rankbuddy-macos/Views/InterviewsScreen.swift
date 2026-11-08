//
//  InterviewsScreen.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

/// The Interviews section: a list of the account's interviews with read-only detail, plus
/// "New Pad" and "Schedule Interview" write actions (#60).
struct InterviewsScreen: View {
    @Environment(AccountStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(AppCommandContext.self) private var commandContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager
    @State private var padPresented = false
    @State private var schedulePresented = false
    @State private var reloadToken = 0

    @State var requestQuery: [URLQueryItem] = []

    var body: some View {
        screen.nativeListFilters("api_list_all_interviews", query: $requestQuery)
    }

    @ViewBuilder private var screen: some View {
        if store.isMergedView {
            mergedList
        } else if let account = store.currentAccount {
            LoadableList(
                title: "Interviews",
                emptyMessage: "No interviews",
                loadPage: { cursor in try await NativeListQuery.page(
                    Interview.self,
                    client: HackerRankClient(account: account),
                    operationID: "api_list_all_interviews",
                    query: requestQuery,
                    cursor: cursor
                ) },
                // The date chip filters server-side over all interviews, not just loaded rows
                // (#86) — the account can have ~87k, so a client-only filter would miss most.
                loadPageInDateRange: { cursor, range in
                    var query = requestQuery
                    if !query.contains(where: { $0.name == "created_at" }),
                       let dates = DateRangeFilter.createdAtServerValue(range) {
                        query.append(URLQueryItem(name: "created_at", value: dates))
                    }
                    return try await NativeListQuery.page(Interview.self, client: HackerRankClient(account: account),
                                                          operationID: "api_list_all_interviews",
                                                          query: query, cursor: cursor)
                },
                searchableText: { "\($0.title ?? "") \($0.status)" },
                sortOptions: [
                    SortOption("Date Created", systemImage: "calendar", kind: .date,
                               isMissing: { DisplayFormat.parseDate($0.createdAt) == nil }, by: {
                                   guard
                                       let lhs = DisplayFormat.parseDate($0.createdAt),
                                       let rhs = DisplayFormat.parseDate($1.createdAt)
                                   else { return false }

                                   return lhs > rhs
                               }),
                    SortOption("Status", systemImage: "circle.fill", kind: .text) {
                        $0.status.localizedStandardCompare($1.status) == .orderedAscending
                    },
                    SortOption("Title", systemImage: "textformat", kind: .text,
                               isMissing: {
                                   $0.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
                               }, by: {
                                   ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending
                               })
                ],
                facets: [
                    ListFacet(
                        "status",
                        "Status",
                        systemImage: "circle.fill",
                        value: { DisplayFormat.enumLabel($0.status) }
                    )
                ],
                restorationKey: requestQuery.isEmpty ? "selection.interviews.\(account.id)" : nil,
                filterDate: { DisplayFormat.parseDate($0.createdAt) },
                dateFilterLabel: "Created",
                contextMenu: { interview in
                    let title = interview.title ?? "Interview \(interview.id)"
                    return rowMenuItems(
                        copyLabel: "Copy Title",
                        copyText: title,
                        link: interview.url,
                        favorite: favorites.menuState(
                            accountID: store.currentAccountID,
                            collection: .interviews,
                            itemID: interview.id,
                            title: title,
                            undoManager: undoManager
                        ),
                        openInWindow: {
                            openWindow(value: DetailWindowValue.interview(interview, accountID: account.id))
                        }
                    )
                },
                openInWindow: { openWindow(value: DetailWindowValue.interview($0, accountID: account.id)) },
                onOpen: { interview in
                    RecentActivityStore.shared.record(
                        [RecentItem(
                            collection: .interviews,
                            id: interview.id,
                            title: interview.title ?? "Interview \(interview.id)",
                            subtitle: DisplayFormat.enumLabel(interview.status)
                        )],
                        for: .interviews,
                        account: account.id
                    )
                },
                onItemsLoaded: { interviews in
                    favorites.refreshMetadata(from: interviews.map {
                        FavoriteRef(
                            accountID: account.id.uuidString,
                            collection: .interviews,
                            itemID: $0.id,
                            title: $0.title ?? "Interview \($0.id)"
                        )
                    })
                },
                accessoryToolbar: { AnyView(newMenu(account: account)) },
                primaryMenuAction: AppCommandContext.Action(title: "New Pad…") { padPresented = true },
                secondaryMenuAction: AppCommandContext.Action(title: "Schedule Interview…") {
                    schedulePresented = true
                },
                reloadToken: reloadToken,
                csvExport: { CSVExport.interviews($0) },
                csvFilename: "interviews",
                favoriteRef: { interview in
                    store.currentAccountID.map {
                        FavoriteRef(
                            accountID: $0.uuidString, collection: .interviews,
                            itemID: interview.id, title: interview.title ?? "Interview \(interview.id)"
                        )
                    }
                },
                rowTransfer: interviewTransfer,
                rowDate: { DisplayFormat.parseDate($0.createdAt) },
                row: { InterviewRow(interview: $0) },
                detail: { InterviewDetailView(interview: $0, account: account) { reloadToken += 1 } }
            )
            .sheet(isPresented: $padPresented) {
                NewPadSheet(account: account) { reloadToken += 1 }
            }
            .sheet(isPresented: $schedulePresented) {
                ScheduleInterviewSheet(account: account) { reloadToken += 1 }
            }
            .onAppear { consumeCreationRequest() }
            .onChange(of: commandContext.creationRequest) { consumeCreationRequest() }
        } else {
            NavigationStack {
                NoAccountView()
                    .navigationTitle("Interviews")
            }
        }
    }

    private func consumeCreationRequest() {
        guard commandContext.creationRequest == .scheduleInterview else { return }

        commandContext.creationRequest = nil
        schedulePresented = true
    }

    private func interviewTransfer(_ interview: Interview) -> RowTransfer {
        let title = interview.title ?? "Interview \(interview.id)"
        let rawURL = interview.url
        return RowTransfer(
            title: title,
            subtitle: DisplayFormat.enumLabel(interview.status),
            url: URL.remoteWebURL(from: rawURL),
            fields: [
                ("Title", title),
                ("Status", DisplayFormat.enumLabel(interview.status)),
                ("Created", interview.createdAt ?? ""),
                ("URL", rawURL)
            ]
        )
    }

    private func mergedInterviewTransfer(_ scoped: AccountScoped<Interview>) -> RowTransfer {
        var transfer = interviewTransfer(scoped.item)
        transfer.subtitle = scoped.account.label
        transfer.fields.insert(("Account", scoped.account.label), at: 1)
        return transfer
    }

    private func newMenu(account _: Account) -> some View {
        Menu {
            Button {
                padPresented = true
            } label: {
                Label("New Pad…", systemImage: "bolt")
            }
            Button {
                schedulePresented = true
            } label: {
                Label("Schedule Interview…", systemImage: "calendar.badge.plus")
            }
        } label: {
            Label("New", systemImage: "plus")
        }
        .help("Create a Pad or schedule an interview")
    }

    /// Loads one merged page of interviews across every configured account (#17).
    private func loadMergedInterviews(_ cursor: String?) async throws -> Page<AccountScoped<Interview>> {
        try await MergedLoader.page(accounts: store.accounts, cursor: cursor) {
            try await NativeListQuery.page(Interview.self, client: HackerRankClient(account: $0),
                                           operationID: "api_list_all_interviews", query: requestQuery, cursor: $1)
        }
    }

    /// Interviews merged across every configured account (#17).
    private var mergedList: some View {
        LoadableList(
            title: "Interviews",
            emptyMessage: "No interviews",
            loadPage: loadMergedInterviews,
            searchableText: { "\($0.item.title ?? "") \($0.item.status) \($0.account.label)" },
            sortOptions: [
                SortOption("Date Created", systemImage: "calendar", kind: .date,
                           isMissing: { DisplayFormat.parseDate($0.item.createdAt) == nil }, by: {
                               guard
                                   let lhs = DisplayFormat.parseDate($0.item.createdAt),
                                   let rhs = DisplayFormat.parseDate($1.item.createdAt)
                               else { return false }

                               return lhs > rhs
                           }),
                SortOption("Account", systemImage: "person.crop.circle", kind: .text,
                           by: AccountScoped.byAccountLabel),
                SortOption("Status", systemImage: "circle.fill", kind: .text) {
                    $0.item.status.localizedStandardCompare($1.item.status) == .orderedAscending
                }
            ],
            contextMenu: { scoped in
                rowMenuItems(
                    copyLabel: "Copy Title",
                    copyText: scoped.item.title ?? "Interview \(scoped.item.id)",
                    link: scoped.item.url,
                    openInWindow: {
                        openWindow(value: DetailWindowValue.interview(scoped.item, accountID: scoped.account.id))
                    }
                )
            },
            openInWindow: {
                openWindow(value: DetailWindowValue.interview($0.item, accountID: $0.account.id))
            },
            rowTransfer: mergedInterviewTransfer,
            rowDate: { DisplayFormat.parseDate($0.item.createdAt) },
            row: {
                MergedRow(
                    title: $0.item.title ?? "Interview \($0.item.id)",
                    subtitle: DisplayFormat.enumLabel($0.item.status),
                    account: $0.account
                )
            },
            detail: { InterviewDetailView(interview: $0.item, account: $0.account) }
        )
    }
}

extension Interview {
    /// A tinted badge for the interview's lifecycle status. Always returns a badge — the
    /// status is required — falling back to a neutral pill with the raw (capitalised) value
    /// for any status not given a dedicated colour.
    var statusBadge: StatusBadge {
        switch status.lowercased() {
        case "completed":
            StatusBadge(text: "Completed", systemImage: "checkmark.circle.fill", tint: .green)
        case "scheduled":
            StatusBadge(text: "Scheduled", systemImage: "calendar", tint: .blue)
        case "in_progress", "in progress":
            StatusBadge(text: "In progress", systemImage: "clock", tint: .orange)
        case "cancelled", "canceled":
            StatusBadge(text: "Cancelled", systemImage: "xmark.circle", tint: .red)
        default:
            StatusBadge(text: DisplayFormat.enumLabel(status), systemImage: "circle", tint: .secondary)
        }
    }
}

/// One row in the interviews list.
struct InterviewRow: View {
    let interview: Interview

    private var displayTitle: String {
        interview.title ?? "Interview \(interview.id)"
    }

    var body: some View {
        HStack {
            Text(displayTitle)
                .listRowTitleStyle(fullText: displayTitle)
                .listRowTextColumn()
            Spacer(minLength: 12)
            interview.statusBadge
        }
    }
}

#Preview("List with date filter") {
    let json = #"""
    [
      {"id":"i1","status":"completed","url":"https://example.com/i1",
       "title":"Senior Backend - Pairing","created_at":"2026-05-05T13:00:00Z"},
      {"id":"i2","status":"scheduled","url":"https://example.com/i2",
       "title":"Frontend - Live Coding","created_at":"2026-05-12T16:00:00Z"}
    ]
    """#
    let interviews = (try? JSONDecoder().decode([Interview].self, from: Data(json.utf8))) ?? []
    return LoadableList(
        title: "Interviews",
        emptyMessage: "No interviews",
        loadPage: { _ in Page(items: interviews, next: nil) },
        searchableText: { "\($0.title ?? "") \($0.status)" },
        restorationKey: "preview.interviews",
        filterDate: { DisplayFormat.parseDate($0.createdAt) },
        dateFilterLabel: "Created",
        row: { InterviewRow(interview: $0) },
        detail: { InterviewDetailView(interview: $0) }
    )
    .frame(width: 520, height: 360)
    .environment(AccountStore.rankBuddy(isTesting: true, seed: [Account(label: "Demo", token: "demo")]))
    .environment(FavoritesStore(isTesting: true))
}

#Preview {
    let json = #"""
    [
      {"id":"i1","status":"completed","url":"https://example.com/i1",
       "title":"Senior Backend - Pairing","created_at":"2026-05-05T13:00:00Z"},
      {"id":"i2","status":"scheduled","url":"https://example.com/i2",
       "title":"Frontend - Live Coding","created_at":"2026-05-12T16:00:00Z"},
      {"id":"i3","status":"cancelled","url":"https://example.com/i3","title":"Platform - Screen"}
    ]
    """#
    let interviews = (try? JSONDecoder().decode([Interview].self, from: Data(json.utf8))) ?? []
    return VStack(alignment: .leading, spacing: 12) {
        ForEach(interviews) { interview in
            InterviewRow(interview: interview)
            Divider()
        }
    }
    .padding()
    .frame(width: 420)
    .environment(AccountStore.rankBuddy(isTesting: true, seed: [Account(label: "Demo", token: "demo")]))
    .environment(FavoritesStore(isTesting: true))
}
