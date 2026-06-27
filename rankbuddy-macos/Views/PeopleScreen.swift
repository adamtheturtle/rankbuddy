//
//  PeopleScreen.swift
//  rankbuddy-macos
//

import BuddyAppKit
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
                loadPage: { try await HackerRankClient(account: account).usersPage(after: $0) },
                searchableText: { "\($0.displayName) \($0.email) \($0.role ?? "")" },
                sortOptions: [
                    SortOption("Name") { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
                    SortOption("Role") { ($0.role ?? "").localizedStandardCompare($1.role ?? "") == .orderedAscending }
                ],
                facets: [
                    ListFacet("role", "Role", systemImage: "person.fill", value: { $0.role?.capitalized }),
                    ListFacet("status", "Status", systemImage: "circle.fill", value: { $0.status?.capitalized })
                ],
                // People is bounded (a few thousand) and the API has no name-search param, so let a
                // search/facet page through the whole list rather than only the first ~1000 (#86).
                searchPageCap: 80,
                restorationKey: "selection.users.\(account.id)",
                contextMenu: { rowMenuItems(copyLabel: "Copy Email", copyText: $0.email) },
                accessoryToolbar: { AnyView(createButton) },
                reloadToken: reloadToken,
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
                        ? "Demo account — no real user is created."
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
