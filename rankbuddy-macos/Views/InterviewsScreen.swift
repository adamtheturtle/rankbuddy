import BuddyAppKit
import SwiftUI

/// The Interviews section: a list of the account's interviews with read-only detail.
struct InterviewsScreen: View {
    @Environment(AccountStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if store.isMergedView {
            mergedList
        } else if let account = store.currentAccount {
            LoadableList(
                title: "Interviews",
                emptyMessage: "No interviews",
                loadPage: { try await HackerRankClient(account: account).interviewsPage(after: $0) },
                searchableText: { "\($0.title ?? "") \($0.status)" },
                sortOptions: [
                    SortOption("Newest") { ($0.createdAt ?? "") > ($1.createdAt ?? "") },
                    SortOption("Status") { $0.status.localizedStandardCompare($1.status) == .orderedAscending },
                    SortOption("Title") {
                        ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending
                    }
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
                csvExport: { CSVExport.interviews($0) },
                csvFilename: "interviews",
                row: { InterviewRow(interview: $0) },
                detail: { InterviewDetailView(interview: $0) }
            )
        } else {
            NavigationStack {
                NoAccountView()
                    .navigationTitle("Interviews")
            }
        }
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
            row: {
                MergedRow(
                    title: $0.item.title ?? "Interview \($0.item.id)",
                    subtitle: $0.item.status.capitalized,
                    accountLabel: $0.account.label
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
    @Environment(AccountStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites

    private var displayTitle: String {
        interview.title ?? "Interview \(interview.id)"
    }

    private var favoriteRef: FavoriteRef? {
        store.currentAccountID.map {
            FavoriteRef(accountID: $0.uuidString, collection: .interviews, itemID: interview.id, title: displayTitle)
        }
    }

    private var isFavorite: Bool {
        guard let favoriteRef else { return false }

        return favorites.isFavorite(collection: .interviews, accountID: favoriteRef.accountID, itemID: interview.id)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle).font(.headline)
                RelativeDateText(iso: interview.createdAt, prefix: "Created")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            FavoriteIndicator(isFavorite: isFavorite)
            interview.statusBadge
        }
        .accessibilityElement(children: .combine)
    }
}

/// Read-only detail for a single interview.
struct InterviewDetailView: View {
    let interview: Interview

    var body: some View {
        Form {
            Section("Interview") {
                OptionalRow("Title", interview.title)
                OptionalRow("Status", interview.status.capitalized)
                OptionalRow("Created", DisplayFormat.date(interview.createdAt))
                OptionalRow("Updated", DisplayFormat.date(interview.updatedAt))
                OptionalRow("Ended", DisplayFormat.date(interview.endedAt))
                OptionalRow("Thumbs up", interview.thumbsUp.map(String.init))

                if let url = URL(string: interview.url) {
                    Link(destination: url) {
                        Label("Open in browser", systemImage: "safari")
                    }
                }

                if let report = interview.reportURL, let url = URL(string: report) {
                    Link(destination: url) {
                        Label("Open report", systemImage: "doc.text")
                    }
                }
            }

            if let notes = interview.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes).textSelection(.enabled)
                }
            }

            if let feedback = interview.feedback, !feedback.isEmpty {
                Section("Feedback") {
                    Text(feedback).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(interview.title ?? "Interview")
        .toolbar {
            ToolbarItem {
                PrintReportButton(jobTitle: "Interview – \(interview.title ?? interview.id)") {
                    InterviewReport(interview: interview)
                }
            }
            ToolbarItem {
                MarkdownExportButton(suggestedName: interview.title ?? "interview-\(interview.id)") {
                    MarkdownExport.interview(interview)
                }
            }
        }
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
