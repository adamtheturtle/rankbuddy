import BuddyAppKit
import SwiftUI

/// The People section: the organisation's users (members), with read-only detail (#36).
struct PeopleScreen: View {
    @Environment(AccountStore.self) private var store

    var body: some View {
        if let account = store.currentAccount {
            LoadableList(
                title: "People",
                emptyMessage: "No people",
                loadPage: { try await HackerRankClient(account: account).usersPage(after: $0) },
                searchableText: { "\($0.displayName) \($0.email) \($0.role ?? "")" },
                sortOptions: [
                    SortOption("Name") { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
                    SortOption("Role") { ($0.role ?? "").localizedStandardCompare($1.role ?? "") == .orderedAscending }
                ],
                restorationKey: "selection.users.\(account.id)",
                contextMenu: { rowMenuItems(copyLabel: "Copy Email", copyText: $0.email) },
                row: { PersonRow(user: $0) },
                detail: { PersonDetailView(user: $0) }
            )
        } else {
            NavigationStack {
                NoAccountView()
                    .navigationTitle("People")
            }
        }
    }
}

extension User {
    /// The user's full name, or their email when no name is set.
    var displayName: String {
        let full = [firstName, lastName].compactMap(\.self).joined(separator: " ")
        return full.isEmpty ? email : full
    }
}

/// One row in the people list.
struct PersonRow: View {
    let user: User

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(user.displayName).font(.headline)
            HStack(spacing: 8) {
                if let role = user.role {
                    Text(role.capitalized)
                }
                if let status = user.status {
                    Text(status.capitalized)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Read-only detail for a single user.
struct PersonDetailView: View {
    let user: User

    var body: some View {
        Form {
            Section("Person") {
                OptionalRow("Name", user.displayName)
                OptionalRow("Email", user.email)
                OptionalRow("Role", user.role?.capitalized)
                OptionalRow("Status", user.status?.capitalized)
                OptionalRow("Country", user.country)
                OptionalRow("Last active", DisplayFormat.date(user.lastActivityTime))
                OptionalRow("Activated", user.activated.map { $0 ? "Yes" : "No" })
                OptionalRow("Company admin", user.companyAdmin == true ? "Yes" : nil)
                OptionalRow("Team admin", user.teamAdmin == true ? "Yes" : nil)
            }

            if let teams = user.teams, !teams.isEmpty {
                Section("Teams") {
                    OptionalRow("Member of", "\(teams.count) team\(teams.count == 1 ? "" : "s")")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(user.displayName)
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
            teams: ["tm1", "tm2"],
            activated: true,
            companyAdmin: true,
            teamAdmin: true,
            lastActivityTime: "2026-06-20T08:30:00Z"
        ))
    }
}
