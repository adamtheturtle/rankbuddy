//
//  PeopleScreen.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

/// The People section: the organisation's users (members), with read-only detail (#36) and
/// a "Create User" write action (#58).
struct PeopleScreen: View {
    @Environment(AccountStore.self) private var store
    @State private var createPresented = false
    @State private var reloadToken = 0

    var body: some View {
        if let account = store.currentAccount {
            LoadableList(
                title: "People",
                emptyMessage: "No people",
                // Browse pages in 100 at a time so the first rows appear immediately instead of
                // waiting for the whole org (thousands of members) to load up front (#108). A
                // search query goes to the server (#104), so a name match isn't gated on having
                // paged that member in; while a facet is active the list auto-pages (bounded by
                // `searchPageCap`) so the facet still scans most of a large org (#86).
                loadPage: { try await HackerRankClient(account: account).usersPage(after: $0) },
                serverSearch: { query, cursor in
                    try await HackerRankClient(account: account).searchUsers(query: query, after: cursor)
                },
                searchableText: { "\($0.displayName) \($0.email) \($0.role ?? "")" },
                sortOptions: [
                    SortOption("Name") { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
                    SortOption("Role") { ($0.role ?? "").localizedStandardCompare($1.role ?? "") == .orderedAscending }
                ],
                facets: [
                    ListFacet("role", "Role", systemImage: "person.fill", value: { $0.role?.capitalized }),
                    ListFacet("status", "Status", systemImage: "circle.fill", value: { $0.status?.capitalized })
                ],
                // People is bounded (a few thousand), so allow a deeper auto-load while a facet
                // filter is active than the default, so the facet scans most of the org (#86).
                searchPageCap: 40,
                restorationKey: "selection.users.\(account.id)",
                contextMenu: { rowMenuItems(copyLabel: "Copy Email", copyText: $0.email) },
                accessoryToolbar: { AnyView(createButton) },
                primaryMenuAction: AppCommandContext.Action(title: "Create User…") { createPresented = true },
                reloadToken: reloadToken,
                rowTransfer: { user in
                    RowTransfer(title: user.displayName, subtitle: user.email, fields: [
                        ("Name", user.displayName),
                        ("Email", user.email),
                        ("Role", user.role?.capitalized ?? ""),
                        ("Status", user.status?.capitalized ?? "")
                    ])
                },
                rowDate: { DisplayFormat.parseDate($0.lastActivityTime) },
                row: { PersonRow(user: $0) },
                detail: { PersonDetailView(user: $0) }
            )
            .sheet(isPresented: $createPresented) {
                CreateUserSheet(account: account) { reloadToken += 1 }
            }
        } else {
            NavigationStack {
                NoAccountView()
                    .navigationTitle("People")
            }
        }
    }

    private var createButton: some View {
        Button {
            createPresented = true
        } label: {
            Label("Create User…", systemImage: "person.badge.plus")
        }
        .help("Create an organisation user")
    }
}

/// A sheet that creates an organisation user (#58) — a write flow. States plainly when it
/// affects a real account, and refreshes the list on success.
struct CreateUserSheet: View {
    let account: Account
    var onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var role = "recruiter"
    @State private var isSending = false
    @State private var errorMessage: String?

    private static let roles = ["recruiter", "interviewer", "developer"]

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .disableAutocorrection(true)
                    TextField("First name (optional)", text: $firstName)
                    TextField("Last name (optional)", text: $lastName)
                    Picker("Role", selection: $role) {
                        ForEach(Self.roles, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                } footer: {
                    Text(account.isMock
                        ? "Demo account: no real user is created."
                        : "This creates a real user in your HackerRank for Work organisation.")
                        .foregroundStyle(account.isMock ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Create User")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Create") { Task { await create() } }
                            .disabled(!EmailValidation.isLikelyValid(email))
                    }
                }
            }
        }
        .frame(width: 440, height: 320)
    }

    private func create() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await HackerRankClient(account: account).createUser(
                email: trimmedEmail, firstName: firstName, lastName: lastName, role: role
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
        VStack(alignment: .leading, spacing: 4) {
            Text(user.displayName).listRowTitleStyle()
            HStack(spacing: 8) {
                if let role = user.role {
                    Text(role.capitalized)
                }
                if let status = user.status {
                    Text(status.capitalized)
                }
            }
            .listRowMetadataStyle()
        }
        // Fill the row width so the content is left-aligned rather than hugging its text and
        // being centred in the column (#111) — the people/teams rows have no trailing badge to
        // stretch them the way the tests/interviews rows do.
        .listRowTextColumn()
        .accessibilityElement(children: .combine)
    }
}

/// Read-only detail for a single user.
struct PersonDetailView: View {
    let user: User

    var body: some View {
        Form {
            InspectorHeader(title: user.displayName, badges: user.inspectorBadges)

            Section("Properties") {
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
