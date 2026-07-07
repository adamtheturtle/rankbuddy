//
//  InterviewsScreen.swift
//  rankbuddy-macos
//

import BuddyAppKit
import SwiftUI

/// The Interviews section: a list of the account's interviews with read-only detail, plus
/// "New QuickPad" and "Schedule Interview" write actions (#60).
struct InterviewsScreen: View {
    @Environment(AccountStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(InterviewTemplatesStore.self) private var templates
    @Environment(InterviewTemplateLauncher.self) private var launcher
    @Environment(\.openWindow) private var openWindow
    @State private var quickPadPresented = false
    @State private var schedulePresented = false
    @State private var templatesPresented = false
    /// A template chosen from the menu/palette, awaiting its pre-filled create sheet (#97).
    @State private var runningTemplate: InterviewTemplate?
    @State private var reloadToken = 0

    var body: some View {
        if store.isMergedView {
            mergedList
        } else if let account = store.currentAccount {
            LoadableList(
                title: "Interviews",
                emptyMessage: "No interviews",
                loadPage: { try await HackerRankClient(account: account).interviewsPage(after: $0) },
                // The date chip filters server-side over all interviews, not just loaded rows
                // (#86) — the account can have ~87k, so a client-only filter would miss most.
                loadPageInDateRange: { cursor, range in
                    try await HackerRankClient(account: account).interviewsPage(
                        after: cursor,
                        createdAtRange: DateRangeFilter.createdAtServerValue(range)
                    )
                },
                searchableText: { "\($0.title ?? "") \($0.status)" },
                sortOptions: [
                    SortOption("Newest") { ($0.createdAt ?? "") > ($1.createdAt ?? "") },
                    SortOption("Status") { $0.status.localizedStandardCompare($1.status) == .orderedAscending },
                    SortOption("Title") {
                        ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending
                    }
                ],
                facets: [
                    ListFacet("status", "Status", systemImage: "circle.fill", value: { $0.status.capitalized })
                ],
                restorationKey: "selection.interviews.\(account.id)",
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
                            title: title
                        ),
                        openInWindow: { openWindow(value: DetailWindowValue.interview(interview)) }
                    )
                },
                onFirstPage: { interviews in
                    RecentActivityStore.shared.record(
                        interviews.map {
                            RecentItem(
                                collection: .interviews,
                                id: $0.id,
                                title: $0.title ?? "Interview \($0.id)",
                                subtitle: $0.status.capitalized
                            )
                        },
                        for: .interviews,
                        account: account.id
                    )
                },
                accessoryToolbar: { AnyView(newMenu(account: account)) },
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
                rowDate: { DisplayFormat.parseDate($0.createdAt) },
                row: { InterviewRow(interview: $0) },
                detail: { InterviewDetailView(interview: $0) }
            )
            .sheet(isPresented: $quickPadPresented) {
                NewQuickPadSheet(account: account) { reloadToken += 1 }
            }
            .sheet(isPresented: $schedulePresented) {
                ScheduleInterviewSheet(account: account) { reloadToken += 1 }
            }
            .sheet(isPresented: $templatesPresented) {
                InterviewTemplatesView(accountID: account.id.uuidString, store: templates)
            }
            // Running a template (from the New menu or the ⌘K palette) opens the matching
            // create flow pre-filled with the template's title (#97).
            .sheet(item: $runningTemplate) { template in
                switch template.kind {
                case .quickPad:
                    NewQuickPadSheet(account: account, initialTitle: template.seededTitle) { reloadToken += 1 }
                case .scheduled:
                    ScheduleInterviewSheet(account: account, initialTitle: template.seededTitle) { reloadToken += 1 }
                }
            }
            // The palette sets a pending template; consume it here so both surfaces drive the
            // same single run path.
            .onChange(of: launcher.pending) { _, new in
                if let new {
                    runningTemplate = new
                    launcher.pending = nil
                }
            }
        } else {
            NavigationStack {
                NoAccountView()
                    .navigationTitle("Interviews")
            }
        }
    }

    private func newMenu(account: Account) -> some View {
        let saved = templates.templates(accountID: account.id.uuidString)
        return Menu {
            Button {
                quickPadPresented = true
            } label: {
                Label("New QuickPad…", systemImage: "bolt")
            }
            Button {
                schedulePresented = true
            } label: {
                Label("Schedule Interview…", systemImage: "calendar.badge.plus")
            }

            Divider()

            if saved.isEmpty {
                Text("No templates yet")
            } else {
                ForEach(saved) { template in
                    Button {
                        runningTemplate = template
                    } label: {
                        Label("Run \(template.name)", systemImage: template.kind.systemImage)
                    }
                }
            }
            Button {
                templatesPresented = true
            } label: {
                Label("Manage Templates…", systemImage: "rectangle.stack")
            }
        } label: {
            Label("New", systemImage: "plus")
        }
        .help("Create a QuickPad, schedule an interview, or run a template")
    }

    /// Loads one merged page of interviews across every configured account (#17).
    private func loadMergedInterviews(_: String?) async throws -> Page<AccountScoped<Interview>> {
        let items = try await MergedLoader.firstPages(accounts: store.accounts) {
            try await HackerRankClient(account: $0).interviewsPage().items
        }
        return Page(items: items, next: nil)
    }

    /// Interviews merged across every configured account (#17).
    private var mergedList: some View {
        LoadableList(
            title: "Interviews",
            emptyMessage: "No interviews",
            loadPage: loadMergedInterviews,
            searchableText: { "\($0.item.title ?? "") \($0.item.status) \($0.account.label)" },
            sortOptions: [
                SortOption("Newest") { ($0.item.createdAt ?? "") > ($1.item.createdAt ?? "") },
                SortOption("Account", by: AccountScoped.byAccountLabel),
                SortOption("Status") {
                    $0.item.status.localizedStandardCompare($1.item.status) == .orderedAscending
                }
            ],
            contextMenu: {
                rowMenuItems(
                    copyLabel: "Copy Title",
                    copyText: $0.item.title ?? "Interview \($0.item.id)",
                    link: $0.item.url
                )
            },
            rowDate: { DisplayFormat.parseDate($0.item.createdAt) },
            row: {
                MergedRow(
                    title: $0.item.title ?? "Interview \($0.item.id)",
                    subtitle: $0.item.status.capitalized,
                    account: $0.account
                )
            },
            detail: { InterviewDetailView(interview: $0.item) }
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
            StatusBadge(text: status.capitalized, systemImage: "circle", tint: .secondary)
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
            Text(displayTitle).font(.callout.weight(.medium))
            Spacer()
            interview.statusBadge
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("List with date filter") {
    let json = #"""
    [
      {"id":"i1","status":"completed","url":"https://example.com/i1",
       "title":"Senior Backend — Pairing","created_at":"2026-05-05T13:00:00Z"},
      {"id":"i2","status":"scheduled","url":"https://example.com/i2",
       "title":"Frontend — Live Coding","created_at":"2026-05-12T16:00:00Z"}
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
       "title":"Senior Backend — Pairing","created_at":"2026-05-05T13:00:00Z"},
      {"id":"i2","status":"scheduled","url":"https://example.com/i2",
       "title":"Frontend — Live Coding","created_at":"2026-05-12T16:00:00Z"},
      {"id":"i3","status":"cancelled","url":"https://example.com/i3","title":"Platform — Screen"}
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
