//
//  PersonDetailView.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

/// The shared explanation for the Lock User confirmations: HackerRank's API deactivates
/// rather than deletes, and the copy says so wherever the action is offered.
enum UserLockCopy {
    static func message(for name: String? = nil) -> String {
        let subject = name.map { "\($0)'s account" } ?? "the account"
        var text = "Locking deactivates \(subject) on HackerRank so this user can no longer sign in."
        text += " HackerRank has no way to fully delete a user."
        return text
    }
}

nonisolated enum UserLockAvailability {
    static func canLock(status: String?, activated: Bool?) -> Bool {
        guard activated != false else { return false }

        let unavailable = ["locked", "inactive", "deactivated", "disabled"]
        return status.map { !unavailable.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
            ?? true
    }
}

nonisolated enum PersonTeamResolution {
    static func labels(ids: [String], namesByID: [String: String]) -> [String] {
        ids.map { namesByID[$0] ?? $0 }
    }

    static func unseenCursor(_ cursor: String?, seen: inout Set<String>) -> String? {
        guard let cursor, seen.insert(cursor).inserted else { return nil }

        return cursor
    }
}

nonisolated struct PersonTeamResolutionKey: Hashable {
    let accountID: UUID?
    let teamIDs: [String]
}

/// Detail for a single user. With an account it is editable in place — name, role, and
/// admin flags save per field (PadBuddy's pad-detail Properties pattern) — and offers a
/// destructive Lock User action; without one it stays read-only (#147).
struct PersonDetailView: View {
    let user: User
    let account: Account?
    var onChanged: () -> Void

    init(user: User, account: Account? = nil, onChanged: @escaping () -> Void = {}) {
        self.user = user
        self.account = account
        self.onChanged = onChanged
    }

    @State private var resolvedTeamNames: [String]?
    @State private var isResolvingTeams = false
    @State private var current: User?
    @State private var editError: String?
    @State private var lockPresented = false
    @State private var wasLocked = false

    /// The freshest copy of the user: server echoes from per-field saves overlay the
    /// (possibly stale) row the list handed us.
    private var displayed: User {
        current ?? user
    }

    private var teamIDs: [String] {
        displayed.teams ?? []
    }

    private var teamResolutionKey: PersonTeamResolutionKey {
        PersonTeamResolutionKey(accountID: account?.id, teamIDs: teamIDs)
    }

    private var displayedTeams: String? {
        if isResolvingTeams {
            return "Loading team names..."
        }

        return DisplayFormat.list(resolvedTeamNames ?? teamIDs)
    }

    private var displayedStatus: String? {
        wasLocked ? "deactivated" : displayed.status
    }

    private var displayedActivated: Bool? {
        wasLocked ? false : displayed.activated
    }

    private var canLock: Bool {
        !wasLocked && UserLockAvailability.canLock(status: displayed.status, activated: displayed.activated)
    }

    var body: some View {
        Form {
            InspectorHeader(title: displayed.displayName, badges: displayed.inspectorBadges)

            Section("Properties") {
                OptionalRow("Email", displayed.email)
                if account == nil {
                    OptionalRow("Role", DisplayFormat.enumLabel(displayed.role))
                } else {
                    editableRows
                }
                OptionalRow("Status", DisplayFormat.enumLabel(displayedStatus))
                OptionalRow("Country", displayed.country)
                OptionalRow("Last active", DisplayFormat.date(displayed.lastActivityTime))
                OptionalRow("Activated", DisplayFormat.boolean(displayedActivated))
                if account == nil {
                    OptionalRow("Company admin", DisplayFormat.boolean(displayed.companyAdmin))
                    OptionalRow("Team admin", DisplayFormat.boolean(displayed.teamAdmin))
                }
            }

            if !teamIDs.isEmpty {
                Section("Teams") {
                    OptionalRow("Member of", displayedTeams)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(displayed.displayName)
        .task(id: teamResolutionKey) {
            await resolveTeamNames()
        }
        .toolbar(id: "personDetail") {
            ToolbarItem(id: "lock") {
                if account != nil {
                    Button(role: .destructive) {
                        lockPresented = true
                    } label: {
                        Label("Lock User", systemImage: "lock")
                    }
                    .disabled(!canLock)
                    .help(canLock ? "Lock this user's account" : "This user is already locked or inactive")
                }
            }
            .defaultCustomization(.hidden)
        }
        .confirmationDialog(
            "Lock \(displayed.displayName)?",
            isPresented: $lockPresented,
            titleVisibility: .visible
        ) {
            Button("Lock User", role: .destructive) {
                Task { await lock() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(UserLockCopy.message())
        }
        .alert("Couldn’t update user", isPresented: editErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editError ?? "")
        }
    }

    /// Per-field editable rows: each saves immediately and reverts if the write fails.
    @ViewBuilder
    private var editableRows: some View {
        EditableTextRow(label: "First name", value: displayed.firstName ?? "") { newValue in
            await save(UserUpdateOptions(firstName: newValue))
        }
        EditableTextRow(label: "Last name", value: displayed.lastName ?? "") { newValue in
            await save(UserUpdateOptions(lastName: newValue))
        }
        EditablePickerRow(
            label: "Role",
            value: displayed.role ?? "recruiter",
            options: organisationUserRoles.map { ($0, DisplayFormat.enumLabel($0)) }
        ) { newValue in
            await save(UserUpdateOptions(role: newValue))
        }
        EditableToggleRow(label: "Company admin", value: displayed.companyAdmin == true) { newValue in
            await save(UserUpdateOptions(companyAdmin: newValue))
        }
        EditableToggleRow(label: "Team admin", value: displayed.teamAdmin == true) { newValue in
            await save(UserUpdateOptions(teamAdmin: newValue))
        }
    }

    private var editErrorPresented: Binding<Bool> {
        Binding(get: { editError != nil }, set: { if !$0 { editError = nil } })
    }

    /// Applies one field's update, then re-reads the user so the detail reflects the
    /// server's view (the write echo can be sparser than the full read).
    private func save(_ options: UserUpdateOptions) async -> Bool {
        guard let account else { return false }

        let client = HackerRankClient(account: account)
        do {
            let updated = try await client.updateUser(id: displayed.id, options: options)
            current = await (try? client.user(id: displayed.id)) ?? updated
            onChanged()
            return true
        } catch {
            editError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func lock() async {
        guard let account, canLock else { return }

        let client = HackerRankClient(account: account)
        do {
            _ = try await client.lockUser(id: displayed.id)
            wasLocked = true
            do {
                current = try await client.user(id: displayed.id)
            } catch {
                editError = "The user was locked, but their latest details couldn’t be refreshed."
            }
            onChanged()
        } catch {
            editError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func resolveTeamNames() async {
        guard let account, !teamIDs.isEmpty else {
            resolvedTeamNames = nil
            return
        }

        isResolvingTeams = true
        defer { isResolvingTeams = false }

        let ids = teamIDs
        let wantedIDs = Set(ids)
        let client = HackerRankClient(account: account)
        var cursor: String?
        var seenCursors: Set<String> = []
        var namesByID: [String: String] = [:]

        do {
            repeat {
                let page = try await client.teamsPage(after: cursor)
                for team in page.items where wantedIDs.contains(team.id) {
                    namesByID[team.id] = team.name
                }
                cursor = PersonTeamResolution.unseenCursor(page.next, seen: &seenCursors)
            } while cursor != nil && namesByID.count < wantedIDs.count

            resolvedTeamNames = PersonTeamResolution.labels(ids: ids, namesByID: namesByID)
        } catch {
            resolvedTeamNames = PersonTeamResolution.labels(ids: ids, namesByID: namesByID)
        }
    }
}

#Preview {
    NavigationStack {
        PersonDetailView(user: User(
            id: "u1",
            email: "rhea@example.com",
            firstName: "Rhea",
            lastName: "Recruiter",
            country: "GB",
            role: "recruiter",
            status: "active",
            teams: ["Platform", "Recruiting Operations"],
            activated: true,
            companyAdmin: true,
            teamAdmin: true,
            lastActivityTime: "2026-06-20T08:30:00Z"
        ))
    }
}
