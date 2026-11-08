//
//  AdministrationScreens.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

struct AdministrationScreen: View {
    enum Destination {
        case audit, ats, provisioning, candidates
        var title: String {
            switch self {
            case .audit: "Audit Logs"
            case .ats: "ATS Invitations"
            case .provisioning: "Provisioning"
            case .candidates: "Find Candidates"
            }
        }
    }

    let destination: Destination
    @Environment(AccountStore.self) private var store
    @State private var accountID: UUID?
    @State private var cursorBased = true
    @State private var interview = false
    @State private var groups = false

    var body: some View {
        VStack(spacing: 0) {
            if !store.accounts.isEmpty {
                HStack(spacing: 20) {
                    Picker("Account", selection: $accountID) {
                        ForEach(store.accounts) { Text($0.label).tag(Optional($0.id)) }
                    }.fixedSize()
                    Spacer(minLength: 16)
                    modePicker
                }
                .padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
                Divider()
            }
            if let account = store.accounts.first(where: { $0.id == accountID }) {
                content(account).id(account)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NoAccountView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(destination.title)
        .onAppear { accountID = store.currentAccountID ?? store.accounts.first?.id }
    }

    @ViewBuilder private var modePicker: some View {
        switch destination {
        case .audit:
            Picker("Pagination", selection: $cursorBased) {
                Text("Cursor").tag(true)
                Text("Offset").tag(false)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 220)

        case .ats:
            Picker("Invitation", selection: $interview) {
                Text("Assessment").tag(false)
                Text("Interview").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 260)

        case .provisioning:
            Picker("Provisioning", selection: $groups) {
                Text("Users").tag(false)
                Text("Groups").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 220)

        case .candidates: EmptyView()
        }
    }

    @ViewBuilder private func content(_ account: Account) -> some View {
        switch destination {
        case .audit: AuditLogsScreen(account: account, cursorBased: cursorBased)
        case .ats: ATSInvitationsScreen(account: account, interview: interview)
        case .provisioning: ProvisioningScreen(account: account, groups: groups)
        case .candidates: BusinessCollectionView(account: account, kind: .candidates, title: "Find Candidates")
        }
    }
}

struct AuditLogsScreen: View {
    let account: Account
    var cursorBased = true
    var body: some View {
        BusinessCollectionView(account: account, kind: cursorBased ? .auditCursor : .auditOffset, title: "Audit Logs")
            .id(cursorBased)
    }
}

struct ATSInvitationsScreen: View {
    let account: Account
    var interview = false
    var body: some View {
        NativeFeatureFormSheet(title: interview ? "ATS Interview Invitation" : "ATS Assessment Invitation",
                               operationID: interview ? "api_ats_interview_invite" : "api_ats_candidate_invite",
                               account: account, embedded: true)
            .id(interview)
    }
}

struct ProvisioningScreen: View {
    let account: Account
    var groups = false
    var body: some View {
        if account.scimToken?.isEmpty == false || account.isMock {
            BusinessCollectionView(account: account, kind: groups ? .provisioningGroups : .provisioningUsers,
                                   title: groups ? "Provisioned Groups" : "Provisioned Users")
                .id(groups)
        } else {
            ContentUnavailableView {
                Label("Provisioning Token Required", systemImage: "key")
            } description: { Text("Add a separate SCIM token for \(account.label) in Account Settings.") }
                actions: { SettingsLink { Text("Account Settings") } }
        }
    }
}

struct BusinessCollectionView: View {
    let account: Account
    let kind: NativeCollectionKind
    let title: String
    @State private var model = NativeBusinessCollection()
    @State private var query: [URLQueryItem] = []
    @State private var filtersPresented = false
    @State private var createPresented = false
    @State private var selected: NativeBusinessRecord?
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if kind == .candidates {
                TextField("Search candidates by name or email", text: $search)
                    .textFieldStyle(.roundedBorder).padding()
            }
            if let error = model.error {
                Text(error).foregroundStyle(.red).padding()
            }
            if let notice = model.notice {
                Text(notice).foregroundStyle(.secondary).padding()
            }
            if kind == .candidates, search.isEmpty {
                ContentUnavailableView("Search Candidates", systemImage: "person.crop.circle.badge.magnifyingglass",
                                       description: Text("Enter a name or email to find candidates across your tests."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                records
            }
            Divider()
            HStack {
                Text("\(model.records.count) loaded").foregroundStyle(.secondary)
                Spacer()
                if model.loading {
                    ProgressView().controlSize(.small)
                }
                if model.nextQuery != nil {
                    Button("Load More") { Task { await load(more: true) } }.disabled(model.loading)
                }
            }.padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(title)
        .toolbar {
            if kind.scim {
                ToolbarItem(id: "provisioning-create", placement: .primaryAction) {
                    Button(kind == .provisioningUsers ? "New User" : "New Group", systemImage: "plus") {
                        createPresented = true
                    }
                }
            }
            ToolbarItem(id: "business-filters", placement: .primaryAction) {
                Button("Filters", systemImage: "line.3.horizontal.decrease") { filtersPresented = true }
            }
            ToolbarItem(id: "business-refresh", placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } }
            }
        }
        .sheet(isPresented: $filtersPresented) { NativeListFiltersSheet(operationID: kind.operationID, query: $query) }
        .sheet(isPresented: $createPresented) {
            NativeFeatureFormSheet(title: kind == .provisioningUsers ? "New Provisioned User" : "New Provisioned Group",
                                   operationID: kind == .provisioningUsers ? "api_scim_create_user" :
                                       "api_scim_create_team",
                                   account: account) { Task { await load() } }
        }
        .task(id: query) { await load() }
        .task(id: search) {
            guard kind == .candidates else { return }

            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            query = query.filter { $0.name != "query" } + [URLQueryItem(name: "query", value: search)]
        }
    }

    private var records: some View {
        HSplitView {
            List(model.records, selection: $selected) { record in
                Text(record.title).tag(record)
            }.frame(minWidth: 260)
            if let selected {
                BusinessRecordDetail(account: account, kind: kind, record: selected) { Task { await load() } }
                    .id(selected.id)
            } else {
                ContentUnavailableView("Select a Record", systemImage: "doc.text.magnifyingglass")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load(more: Bool = false) async {
        if kind == .candidates, query.first(where: { $0.name == "query" })?.value?.isEmpty != false {
            model.clear()
            selected = nil
            return
        }
        if !more {
            selected = nil
        }
        await model.load(kind: kind, client: HackerRankClient(account: account),
                         scimToken: account.isMock ? "demo-scim" : account.scimToken, query: query, more: more)
    }
}

struct BusinessRecordDetail: View {
    let account: Account
    let kind: NativeCollectionKind
    let record: NativeBusinessRecord
    let onSaved: () -> Void
    @State private var detail: HackerRankJSONValue?
    @State private var error: String?

    var body: some View {
        Form {
            if let error {
                Text(error).foregroundStyle(.red)
            }
            NativeRecordContent(value: detail ?? record.value)
        }
        .formStyle(.grouped)
        .nativeResourceActions(kind == .provisioningUsers ? .provisioningUser : .provisioningGroup,
                               account: kind.scim ? account : nil, path: ["id": record.id], onSaved: onSaved)
        .task {
            guard kind.scim else { return }

            do {
                detail = try await HackerRankClient(account: account).executeAPI(
                    kind == .provisioningUsers ? "api_scim_retrieve_user" : "api_scim_retrieve_team",
                    pathParameters: ["id": record.id], scimToken: account.isMock ? "demo-scim" : account.scimToken
                ).data
            } catch { self.error = rankCoverageError(error) }
        }
    }
}
