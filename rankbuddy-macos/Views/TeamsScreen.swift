import BuddyAppKit
import FastList
import SwiftUI

/// The Teams section: the organisation's teams, with read-only detail (#36) and an opt-in
/// "New Team" write action (#59).
struct TeamsScreen: View {
    @Environment(AccountStore.self) private var store
    @AppStorage(WriteActions.defaultsKey) private var writeActionsEnabled = false
    @State private var createPresented = false
    @State private var reloadToken = 0

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
                accessoryToolbar: { writeActionsEnabled ? AnyView(createButton) : AnyView(EmptyView()) },
                reloadToken: reloadToken,
                row: { TeamRow(team: $0) },
                detail: { TeamDetailView(team: $0, account: account) }
            )
            .sheet(isPresented: $createPresented) {
                CreateTeamSheet(account: account) { reloadToken += 1 }
            }
        } else {
            NavigationStack {
                NoAccountView()
                    .navigationTitle("Teams")
            }
        }
    }

    private var createButton: some View {
        Button {
            createPresented = true
        } label: {
            Label("New Team…", systemImage: "person.3")
        }
        .help("Create a team")
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

/// The members of a team, pushed from `TeamDetailView`. Read-only list + detail (#56), with
/// opt-in "Add Member" and per-row "Remove from Team" write actions (#59).
struct TeamMembersList: View {
    let teamID: String
    let account: Account

    @AppStorage(WriteActions.defaultsKey) private var writeActionsEnabled = false
    @State private var addPresented = false
    @State private var memberPendingRemoval: User?
    @State private var removalError: String?
    @State private var reloadToken = 0

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
            contextMenu: { memberMenuItems(for: $0) },
            accessoryToolbar: { writeActionsEnabled ? AnyView(addButton) : AnyView(EmptyView()) },
            reloadToken: reloadToken,
            row: { PersonRow(user: $0) },
            detail: { PersonDetailView(user: $0) }
        )
        .sheet(isPresented: $addPresented) {
            AddTeamMemberSheet(teamID: teamID, account: account) { reloadToken += 1 }
        }
        .confirmationDialog(
            "Remove member?",
            isPresented: removalDialogPresented,
            presenting: memberPendingRemoval
        ) { member in
            Button("Remove \(member.displayName)", role: .destructive) {
                Task { await remove(member) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { member in
            Text(account.isMock
                ? "Demo account — \(member.displayName) is not really removed."
                : "This removes \(member.displayName) from the team on HackerRank.")
        }
        .alert("Couldn’t remove member", isPresented: removalErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(removalError ?? "")
        }
    }

    private var addButton: some View {
        Button {
            addPresented = true
        } label: {
            Label("Add Member…", systemImage: "person.badge.plus")
        }
        .help("Add a member to this team")
    }

    private func memberMenuItems(for member: User) -> [MenuItem] {
        var items = rowMenuItems(copyLabel: "Copy Email", copyText: member.email)
        if writeActionsEnabled {
            items.append(.separator)
            items.append(.button(title: "Remove from Team…") { memberPendingRemoval = member })
        }
        return items
    }

    private var removalDialogPresented: Binding<Bool> {
        Binding(get: { memberPendingRemoval != nil }, set: { if !$0 { memberPendingRemoval = nil } })
    }

    private var removalErrorPresented: Binding<Bool> {
        Binding(get: { removalError != nil }, set: { if !$0 { removalError = nil } })
    }

    private func remove(_ member: User) async {
        do {
            try await HackerRankClient(account: account).removeTeamMember(teamID: teamID, userID: member.id)
            reloadToken += 1
        } catch {
            removalError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
