import BuddyAppKit
import SwiftUI

/// The Teams section: the organisation's teams, with read-only detail (#36).
struct TeamsScreen: View {
    @Environment(AccountStore.self) private var store

    var body: some View {
        if let account = store.currentAccount {
            LoadableList(
                title: "Teams",
                emptyMessage: "No teams",
                loadPage: { try await HackerRankClient(account: account).teamsPage(after: $0) },
                searchableText: { "\($0.name) \($0.departments?.joined(separator: " ") ?? "")" },
                sortOptions: [
                    SortOption("Name") { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                    SortOption("Size") { ($0.developerCount ?? 0) > ($1.developerCount ?? 0) }
                ],
                restorationKey: "selection.teams.\(account.id)",
                contextMenu: { rowMenuItems(copyLabel: "Copy Name", copyText: $0.name) },
                row: { TeamRow(team: $0) },
                detail: { TeamDetailView(team: $0, account: account) }
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
        if let interviewerCount {
            parts.append("\(interviewerCount) interviewer\(interviewerCount == 1 ? "" : "s")")
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
    }
}

/// The members of a team, pushed from `TeamDetailView`. Read-only list + detail (#56).
struct TeamMembersList: View {
    let teamID: String
    let account: Account

    var body: some View {
        LoadableList(
            title: "Members",
            emptyMessage: "No members",
            loadPage: {
                try await HackerRankClient(account: account).teamMembersPage(teamID: teamID, after: $0)
            },
            searchableText: { "\($0.displayName) \($0.email) \($0.role ?? "")" },
            sortOptions: [
                SortOption("Name") { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
                SortOption("Role") { ($0.role ?? "").localizedStandardCompare($1.role ?? "") == .orderedAscending }
            ],
            contextMenu: { rowMenuItems(copyLabel: "Copy Email", copyText: $0.email) },
            row: { PersonRow(user: $0) },
            detail: { PersonDetailView(user: $0) }
        )
    }
}

/// Read-only detail for a single team.
struct TeamDetailView: View {
    let team: Team
    let account: Account

    var body: some View {
        Form {
            Section("Team") {
                OptionalRow("Name", team.name)
                OptionalRow("Recruiters", team.recruiterCount.map { "\($0)" })
                OptionalRow("Developers", team.developerCount.map { "\($0)" })
                OptionalRow("Interviewers", team.interviewerCount.map { "\($0)" })
                OptionalRow("Created", DisplayFormat.date(team.createdAt))
                OptionalRow("Locations", DisplayFormat.list(team.locations))
            }

            Section {
                NavigationLink {
                    TeamMembersList(teamID: team.id, account: account)
                } label: {
                    Label("Members", systemImage: "person.2")
                }
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
            interviewerCount: 8,
            locations: ["London", "Berlin"],
            departments: ["Engineering", "Platform"]
        ), account: Account(label: "Demo", token: "demo"))
    }
}
