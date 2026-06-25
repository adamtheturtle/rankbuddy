import BuddyAppKit
import SwiftUI

/// The Teams section: the organisation's teams, with read-only detail (#36).
struct TeamsScreen: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.hackerRankSession) private var session

    var body: some View {
        if let account = store.currentAccount {
            LoadableList(
                title: "Teams",
                emptyMessage: "No teams",
                loadPage: { try await HackerRankClient(account: account, session: session).teamsPage(after: $0) },
                searchableText: { "\($0.name) \($0.departments?.joined(separator: " ") ?? "")" },
                sortOptions: [
                    SortOption("Name") { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                    SortOption("Size") { ($0.developerCount ?? 0) > ($1.developerCount ?? 0) }
                ],
                restorationKey: "selection.teams.\(account.id)",
                row: { TeamRow(team: $0) },
                detail: { TeamDetailView(team: $0) }
            )
        } else {
            NavigationStack {
                NoAccountView()
                    .navigationTitle("Teams")
            }
        }
    }
}

extension Team {
    /// A short "N recruiters · M developers" summary, omitting absent counts.
    var memberSummary: String? {
        var parts: [String] = []
        if let recruiterCount {
            parts.append("\(recruiterCount) recruiter\(recruiterCount == 1 ? "" : "s")")
        }
        if let developerCount {
            parts.append("\(developerCount) developer\(developerCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One row in the teams list.
struct TeamRow: View {
    let team: Team

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(team.name).font(.headline)
            if let summary = team.memberSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .rowContextMenu(copyLabel: "Copy Name", copyText: team.name)
    }
}

/// Read-only detail for a single team.
struct TeamDetailView: View {
    let team: Team

    var body: some View {
        Form {
            Section("Team") {
                OptionalRow("Name", team.name)
                OptionalRow("Recruiters", team.recruiterCount.map { "\($0)" })
                OptionalRow("Developers", team.developerCount.map { "\($0)" })
                OptionalRow("Created", DisplayFormat.date(team.createdAt))
                OptionalRow("Locations", DisplayFormat.list(team.locations))
            }

            if let departments = team.departments, !departments.isEmpty {
                Section("Departments") {
                    TagList(tags: departments)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(team.name)
    }
}

#Preview {
    NavigationStack {
        TeamDetailView(team: Team(
            id: "tm1",
            name: "Backend Hiring",
            owner: "u1",
            createdAt: "2026-04-01T09:00:00Z",
            recruiterCount: 3,
            developerCount: 12,
            locations: ["London", "Berlin"],
            departments: ["Engineering", "Platform"]
        ))
    }
}
