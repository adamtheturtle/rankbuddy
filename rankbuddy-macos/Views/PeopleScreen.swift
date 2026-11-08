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
    @Environment(AccountStore.self) var store
    @Environment(\.openWindow) var openWindow
    @State private var createPresented = false
    @State var reloadToken = 0
    @State private var userPendingLock: User?
    @State private var lockError: String?

    @State var requestQuery: [URLQueryItem] = []

    var body: some View {
        screen.nativeListFilters("api_list_all_users", query: $requestQuery)
    }

    @ViewBuilder private var screen: some View {
        if store.isMergedView {
            mergedList
        } else if let account = store.currentAccount {
            LoadableList(
                title: "People",
                emptyMessage: "No people",
                // Browse pages in 100 at a time so the first rows appear immediately instead of
                // waiting for the whole org (thousands of members) to load up front (#108). A
                // search query goes to the server (#104), so a name match isn't gated on having
                // paged that member in; while a facet is active the list auto-pages (bounded by
                // `searchPageCap`) so the facet still scans most of a large org (#86).
                loadPage: { cursor in try await NativeListQuery.page(
                    User.self,
                    client: HackerRankClient(account: account),
                    operationID: "api_list_all_users",
                    query: requestQuery,
                    cursor: cursor
                ) },
                serverSearch: { query, cursor in
                    try await NativeListQuery.page(User.self, client: HackerRankClient(account: account),
                                                   operationID: "api_search_users",
                                                   query: requestQuery + [URLQueryItem(name: "search", value: query)],
                                                   cursor: cursor)
                },
                searchableText: { "\($0.displayName) \($0.email) \($0.role ?? "")" },
                sortOptions: [
                    SortOption("Name", systemImage: "textformat", kind: .text) {
                        $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                    },
                    SortOption("Role", systemImage: "person.text.rectangle", kind: .text,
                               isMissing: {
                                   $0.role?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
                               }, by: {
                                   ($0.role ?? "").localizedStandardCompare($1.role ?? "") == .orderedAscending
                               })
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
                restorationKey: requestQuery.isEmpty ? "selection.users.\(account.id)" : nil,
                contextMenu: { user in
                    var items = rowMenuItems(
                        copyLabel: "Copy Email",
                        copyText: user.email,
                        openInWindow: {
                            openWindow(value: DetailWindowValue.userWindow(user, accountID: account.id))
                        }
                    )
                    items.append(.separator)
                    items.append(.button(title: "Lock User…") { userPendingLock = user })
                    return items
                },
                openInWindow: { openWindow(value: DetailWindowValue.userWindow($0, accountID: account.id)) },
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
                CreateUserSheet(account: account) {
                    reloadToken += 1
                }
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
        Binding(get: { userPendingLock != nil }, set: {
            if !$0 {
                userPendingLock = nil
            }
        })
    }

    private var lockErrorPresented: Binding<Bool> {
        Binding(get: { lockError != nil }, set: {
            if !$0 {
                lockError = nil
            }
        })
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
