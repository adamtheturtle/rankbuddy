//
//  PeopleScreen.swift
//  rankbuddy-macos
//

import BuddyAppKit
import FastList
import HackerRankKit
import SwiftUI

/// The roles HackerRank accepts for an organisation user, shared by the create sheet
/// and the detail view's role picker.
let organisationUserRoles = ["recruiter", "interviewer", "developer"]

/// The People section: the organisation's users (members), with read-only detail (#36) and
/// a "Create User" write action (#58).
struct PeopleScreen: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var createPresented = false
    @State private var reloadToken = 0
    @State private var userPendingLock: User?
    @State private var lockError: String?

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
                    SortOption("Name", systemImage: "textformat", kind: .text) {
                        $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                    },
                    SortOption("Role", systemImage: "person.text.rectangle", kind: .text) {
                        ($0.role ?? "").localizedStandardCompare($1.role ?? "") == .orderedAscending
                    }
                ],
                facets: [
                    ListFacet("role", "Role", systemImage: "person.fill", value: { DisplayFormat.enumLabel($0.role) }),
                    ListFacet(
                        "status",
                        "Status",
                        systemImage: "circle.fill",
                        value: { DisplayFormat.enumLabel($0.status) }
                    )
                ],
                // People is bounded (a few thousand), so allow a deeper auto-load while a facet
                // filter is active than the default, so the facet scans most of the org (#86).
                searchPageCap: 40,
                restorationKey: "selection.users.\(account.id)",
                contextMenu: { user in
                    var items = rowMenuItems(
                        copyLabel: "Copy Email",
                        copyText: user.email,
                        openInWindow: { openWindow(value: DetailWindowValue.user(user, accountID: account.id)) }
                    )
                    items.append(.separator)
                    items.append(.button(title: "Lock User…") { userPendingLock = user })
                    return items
                },
                openInWindow: { openWindow(value: DetailWindowValue.user($0, accountID: account.id)) },
                accessoryToolbar: { AnyView(createButton) },
                primaryMenuAction: AppCommandContext.Action(title: "Create User…") { createPresented = true },
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
            .sheet(isPresented: $createPresented) {
                CreateUserSheet(account: account) { reloadToken += 1 }
            }
            .confirmationDialog(
                "Lock user?",
                isPresented: lockDialogPresented,
                titleVisibility: .visible,
                presenting: userPendingLock
            ) { user in
                Button("Lock \(user.displayName)", role: .destructive) {
                    Task { await lock(user, account: account) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { user in
                Text(UserLockCopy.message(for: user.displayName))
            }
            .alert("Couldn’t lock user", isPresented: lockErrorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(lockError ?? "")
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

    private var lockDialogPresented: Binding<Bool> {
        Binding(get: { userPendingLock != nil }, set: { if !$0 { userPendingLock = nil } })
    }

    private var lockErrorPresented: Binding<Bool> {
        Binding(get: { lockError != nil }, set: { if !$0 { lockError = nil } })
    }

    private func lock(_ user: User, account: Account) async {
        do {
            _ = try await HackerRankClient(account: account).lockUser(id: user.id)
            reloadToken += 1
        } catch {
            lockError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// A sheet that creates an organisation user (#58) — a write flow. Refreshes the list on success.
struct CreateUserSheet: View {
    let account: Account
    var onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var role = "recruiter"
    @State private var teams: [Team] = []
    @State private var selectedTeamID: String?
    @State private var teamsError: String?
    @State private var isSending = false
    @State private var errorMessage: String?

    private static let roles = organisationUserRoles

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLastName: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEmailValid: Bool {
        EmailValidation.isLikelyValid(email)
    }

    /// The API requires email, firstname, role, and at least one team on POST /users (it
    /// rejects the request with HTTP 400 "Parameter … is required" otherwise); the last
    /// name is genuinely optional.
    private var canCreate: Bool {
        isEmailValid && !trimmedFirstName.isEmpty && selectedTeamID != nil
    }

    private var shouldShowEmailValidation: Bool {
        !trimmedEmail.isEmpty && !isEmailValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .disableAutocorrection(true)
                    if shouldShowEmailValidation {
                        Label(
                            "Enter a valid email address, for example name@example.com.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                    TextField("First name", text: $firstName)
                    TextField("Last name (optional)", text: $lastName)
                    Picker("Role", selection: $role) {
                        ForEach(Self.roles, id: \.self) { Text(DisplayFormat.enumLabel($0)).tag($0) }
                    }
                    Picker("Team", selection: $selectedTeamID) {
                        Text(teams.isEmpty ? "Loading teams…" : "Choose a team").tag(String?.none)
                        ForEach(teams) { team in
                            Text(team.name).tag(Optional(team.id))
                        }
                    }
                    if let teamsError {
                        Label(teamsError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                            .disabled(!canCreate)
                            .help(canCreate
                                ? "Create user"
                                : "Enter a valid email address, a first name, and a team to create a user")
                    }
                }
            }
        }
        // Grow the sheet when the error section appears so the form doesn't have to scroll to
        // show it (server messages can wrap to a few lines).
        .frame(width: 440, height: errorMessage == nil ? 360 : 460)
        .task { await loadTeams() }
    }

    /// Loads the organisation's teams for the required team picker, following the cursor
    /// so orgs with more than one page are fully listed (bounded to stay snappy).
    private func loadTeams() async {
        teamsError = nil
        let client = HackerRankClient(account: account)
        var loaded: [Team] = []
        var cursor: String?
        do {
            repeat {
                let page = try await client.teamsPage(after: cursor)
                loaded.append(contentsOf: page.items)
                cursor = page.next
            } while cursor != nil && loaded.count < 1000
            teams = loaded
            if teams.isEmpty {
                teamsError = "No teams found. HackerRank requires a team to create a user."
            }
        } catch {
            // A failed follow-up page keeps the teams already loaded — the picker is still
            // usable; only surface the error when there is nothing to choose from.
            if loaded.isEmpty {
                teamsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            } else {
                teams = loaded
            }
        }
    }

    private func create() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        guard let selectedTeamID else { return }

        do {
            try await HackerRankClient(account: account).createUser(
                email: trimmedEmail,
                firstName: trimmedFirstName,
                lastName: trimmedLastName,
                role: role,
                teamIDs: [selectedTeamID]
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

extension User {
    /// The user's full name, or their email when no name is set. `nonisolated` so the
    /// nonisolated `DetailWindowValue.windowTitle` can use it — it's pure computation.
    nonisolated var displayName: String {
        let full = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return full.isEmpty ? email : full
    }
}

/// One row in the people list.
struct PersonRow: View {
    let user: User

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(user.displayName).listRowTitleStyle(fullText: user.displayName)
            HStack(spacing: 8) {
                if let role = user.role {
                    Text(DisplayFormat.enumLabel(role))
                }
                if let status = user.status {
                    Text(DisplayFormat.enumLabel(status))
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
