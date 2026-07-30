//
//  TeamsScreen.swift
//  rankbuddy-macos
//

import BuddyAppKit
import FastList
import HackerRankKit
import SwiftUI

/// The Teams section: the organisation's teams, with read-only detail (#36) and a
/// "New Team" write action (#59).
struct TeamsScreen: View {
    @Environment(AccountStore.self) var store
    @Environment(\.openWindow) var openWindow
    @State private var createPresented = false
    @State var reloadToken = 0

    var body: some View {
        if store.isMergedView {
            mergedList
        } else if let account = store.currentAccount {
            LoadableList(
                title: "Teams",
                emptyMessage: "No teams",
                loadPage: { try await HackerRankClient(account: account).teamsPage(after: $0) },
                searchableText: { "\($0.name) \($0.departments?.joined(separator: " ") ?? "")" },
                sortOptions: [
                    SortOption("Name", systemImage: "textformat", kind: .text) {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    },
                    SortOption("Size", systemImage: "person.3", kind: .amount) {
                        ($0.developerCount ?? 0) > ($1.developerCount ?? 0)
                    }
                ],
                facets: [
                    ListFacet("department", "Department", systemImage: "building.2") { $0.departments ?? [] },
                    ListFacet("location", "Location", systemImage: "mappin.and.ellipse") { $0.locations ?? [] }
                ],
                restorationKey: "selection.teams.\(account.id)",
                contextMenu: { team in
                    rowMenuItems(
                        copyLabel: "Copy Name",
                        copyText: team.name,
                        openInWindow: {
                            openWindow(value: DetailWindowValue.teamWindow(team, accountID: account.id))
                        }
                    )
                },
                openInWindow: {
                    openWindow(value: DetailWindowValue.teamWindow($0, accountID: account.id))
                },
                accessoryToolbar: { AnyView(createButton) },
                primaryMenuAction: AppCommandContext.Action(title: "New Team…") { createPresented = true },
                reloadToken: reloadToken,
                rowTransfer: { team in
                    RowTransfer(title: team.name, subtitle: team.memberSummary, fields: team.transferFields)
                },
                rowDate: { DisplayFormat.parseDate($0.createdAt) },
                row: { TeamRow(team: $0) },
                detail: { TeamDetailView(team: $0, account: account) { reloadToken += 1 } }
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
            Label("New Team…", systemImage: "person.2.badge.plus")
        }
        .help("Create a team")
    }
}

extension Team {
    /// The explicit columns used by copy, drag, and tabular exports.
    var transferFields: [(String, String)] {
        [
            ("Name", name),
            ("Members", memberSummary ?? ""),
            ("Recruiters", recruiterCount.map(String.init) ?? ""),
            ("Developers", developerCount.map(String.init) ?? ""),
            ("Interviewers", interviewerCount.map(String.init) ?? "")
        ]
    }

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
        VStack(alignment: .leading, spacing: 4) {
            Text(team.name).listRowTitleStyle(fullText: team.name)
            if let summary = team.memberSummary {
                Text(summary)
                    .listRowMetadataStyle()
            }
        }
        // Fill the row width so the content is left-aligned rather than centred in the column
        // (#111) — teams rows carry no trailing badge to stretch them like the other lists.
        .listRowTextColumn()
        .accessibilityElement(children: .combine)
    }
}

/// The members of a team, opened in its own window from `TeamDetailView`. Read-only list +
/// detail (#56), with
/// "Add Member" and per-row "Remove from Team" write actions (#59).
struct TeamMembersList: View {
    let teamID: String
    let account: Account

    @Environment(\.openWindow) private var openWindow
    @State private var addPresented = false
    @State private var memberPendingRemoval: User?
    @State private var removingMemberIDs: Set<String> = []
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
                SortOption("Name", systemImage: "textformat", kind: .text) {
                    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                },
                SortOption("Role", systemImage: "person.text.rectangle", kind: .text) {
                    ($0.role ?? "").localizedStandardCompare($1.role ?? "") == .orderedAscending
                }
            ],
            contextMenu: { memberMenuItems(for: $0) },
            openInWindow: { openWindow(value: DetailWindowValue.user($0, accountID: account.id)) },
            accessoryToolbar: { AnyView(addButton) },
            reloadToken: reloadToken,
            rowTransfer: { user in
                RowTransfer(title: user.displayName, subtitle: user.email, fields: [
                    ("Name", user.displayName),
                    ("Email", user.email),
                    ("Role", DisplayFormat.enumLabel(user.role) ?? ""),
                    ("Status", DisplayFormat.enumLabel(user.status) ?? "")
                ])
            },
            rowDate: { DisplayFormat.parseDate($0.lastActivityTime) },
            row: { PersonRow(user: $0) },
            detail: { PersonDetailView(user: $0, account: account) { reloadToken += 1 } }
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
                beginRemoval(member)
            }
            .disabled(removingMemberIDs.contains(member.id))
            Button("Cancel", role: .cancel) {}
        } message: { member in
            Text("This removes \(member.displayName) from the team on HackerRank.")
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
        var items = rowMenuItems(
            copyLabel: "Copy Email",
            copyText: member.email,
            openInWindow: { openWindow(value: DetailWindowValue.user(member, accountID: account.id)) }
        )
        items.append(.separator)
        let isRemoving = removingMemberIDs.contains(member.id)
        items.append(.button(
            title: isRemoving ? "Removing…" : "Remove from Team…",
            isEnabled: !isRemoving
        ) { memberPendingRemoval = member })
        return items
    }

    private var removalDialogPresented: Binding<Bool> {
        Binding(get: { memberPendingRemoval != nil }, set: { if !$0 { memberPendingRemoval = nil } })
    }

    private var removalErrorPresented: Binding<Bool> {
        Binding(get: { removalError != nil }, set: { if !$0 { removalError = nil } })
    }

    private func beginRemoval(_ member: User) {
        guard removingMemberIDs.insert(member.id).inserted else { return }

        Task { await remove(member) }
    }

    private func remove(_ member: User) async {
        defer { removingMemberIDs.remove(member.id) }
        do {
            try await HackerRankClient(account: account).removeTeamMember(teamID: teamID, userID: member.id)
            reloadToken += 1
        } catch {
            removalError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Detail for a single team. The title renames in place (#95's pattern) and the locations
/// and departments save per field via `updateTeam` (#147); the rest stays read-only.
struct TeamDetailView: View {
    let team: Team
    let account: Account
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var deletePresented = false
    @State private var deleteError: String?
    @State private var current: Team?
    @State private var editError: String?

    /// The freshest copy of the team: server echoes from per-field saves overlay the
    /// (possibly stale) row the list handed us.
    private var displayed: Team {
        current ?? team
    }

    var body: some View {
        Form {
            InspectorHeader(
                title: displayed.name,
                badges: displayed.inspectorBadges,
                onRename: { newName in await save(TeamUpdateOptions(name: newName)) }
            )

            Section("Properties") {
                OptionalRow("Recruiters", displayed.recruiterCount.map { "\($0)" })
                OptionalRow("Developers", displayed.developerCount.map { "\($0)" })
                OptionalRow("Interviewers", displayed.interviewerCount.map { "\($0)" })
                OptionalRow("Created", DisplayFormat.date(displayed.createdAt))
                EditableTextRow(
                    label: "Locations",
                    value: displayed.locations?.joined(separator: ", ") ?? "",
                    prompt: "Comma-separated"
                ) { newValue in
                    await save(TeamUpdateOptions(locations: Self.splitList(newValue)))
                }
            }

            Section("Participants") {
                WindowLinkRow(
                    title: "Members",
                    systemImage: "person.2",
                    value: .teamMembers(teamID: team.id, teamName: displayed.name, accountID: account.id)
                )
            }

            Section("Departments") {
                EditableTextRow(
                    label: "Departments",
                    value: displayed.departments?.joined(separator: ", ") ?? "",
                    prompt: "Comma-separated"
                ) { newValue in
                    await save(TeamUpdateOptions(departments: Self.splitList(newValue)))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(displayed.name)
        .toolbar(id: "teamDetail") {
            ToolbarItem(id: "delete") {
                Button(role: .destructive) {
                    deletePresented = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete this team")
            }
            .defaultCustomization(.hidden)
        }
        .confirmationDialog("Delete “\(displayed.name)”?", isPresented: $deletePresented, titleVisibility: .visible) {
            Button("Delete Team", role: .destructive) {
                Task { await deleteTeam() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the team on HackerRank. This can’t be undone.")
        }
        .alert("Couldn’t delete team", isPresented: deleteErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .alert("Couldn’t update team", isPresented: editErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editError ?? "")
        }
    }

    private var deleteErrorPresented: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    }

    private var editErrorPresented: Binding<Bool> {
        Binding(get: { editError != nil }, set: { if !$0 { editError = nil } })
    }

    /// "a, b, c" → ["a", "b", "c"]; nil when the field is cleared entirely.
    private static func splitList(_ text: String) -> [String]? {
        let parts = text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts
    }

    /// Applies one field's update, then re-reads the team so the detail reflects the
    /// server's view (the write echo can be sparser than the full read).
    private func save(_ options: TeamUpdateOptions) async -> Bool {
        let client = HackerRankClient(account: account)
        do {
            let updated = try await client.updateTeam(id: team.id, options: options)
            current = await (try? client.team(id: team.id)) ?? updated
            onChanged()
            return true
        } catch {
            editError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func deleteTeam() async {
        do {
            try await HackerRankClient(account: account).deleteTeam(id: team.id)
            onChanged()
            dismiss()
        } catch {
            deleteError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
