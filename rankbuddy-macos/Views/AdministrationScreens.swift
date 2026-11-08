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
    @Environment(AppCommandContext.self) private var commandContext
    @State private var model = NativeBusinessCollection()
    @State private var query: [URLQueryItem] = []
    @State private var filtersPresented = false
    @State private var createPresented = false
    @State private var selected: NativeBusinessRecord?
    @State private var search = ""
    @State private var commandOwner = UUID()

    private var hasSearch: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if kind == .candidates {
                TextField("Search candidates by name or email", text: $search)
                    .textFieldStyle(.roundedBorder).padding()
                    .accessibilityLabel("Search Candidates")
            }
            if let error = model.error, !model.records.isEmpty {
                Text(error).foregroundStyle(.red).padding()
            }
            if let notice = model.notice {
                Text(notice).foregroundStyle(.secondary).padding()
            }
            if kind == .candidates, !hasSearch {
                ContentUnavailableView("Search Candidates", systemImage: "person.crop.circle.badge.magnifyingglass",
                                       description: Text("Enter a name or email to find candidates across your tests."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.records.isEmpty, model.loading {
                CompactStateView(title: kind == .candidates ? "Searching Candidates" : "Loading \(title)",
                                 systemImage: "arrow.triangle.2.circlepath", message: "Getting the latest records.",
                                 isLoading: true)
            } else if let error = model.error, model.records.isEmpty {
                CompactStateView(title: "Couldn’t Load \(title)", systemImage: "exclamationmark.triangle",
                                 message: error,
                                 actionTitle: "Try Again", actionSystemImage: "arrow.clockwise") {
                    Task { await load() }
                }
            } else if model.records.isEmpty {
                CompactStateView(title: kind == .candidates ? "No Candidates Found" : "No Records",
                                 systemImage: "magnifyingglass",
                                 message: kind == .candidates ? "Try a different name or email." :
                                     "Try changing the filters for this account.")
            } else {
                records
            }
            if kind != .candidates || hasSearch {
                collectionFooter
            }
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
                    .disabled(model.loading || (kind == .candidates && !hasSearch))
            }
        }
        .sheet(isPresented: $filtersPresented) {
            NativeListFiltersSheet(operationID: kind.operationID, query: $query, collectionTitle: title,
                                   excludedNames: kind == .candidates ? ["query"] : [])
        }
        .sheet(isPresented: $createPresented) {
            NativeFeatureFormSheet(title: kind == .provisioningUsers ? "New Provisioned User" : "New Provisioned Group",
                                   operationID: kind == .provisioningUsers ? "api_scim_create_user" :
                                       "api_scim_create_team",
                                   account: account) { Task { await load() } }
        }
        .task(id: query) { await load() }
        .onAppear { registerCommands() }
        .activatesListCommands(in: commandContext, owner: commandOwner)
        .onDisappear { commandContext.clearListActions(owner: commandOwner) }
        .task(id: search) {
            guard kind == .candidates else { return }

            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            query = query.filter { $0.name != "query" }
                + [URLQueryItem(name: "query", value: search.trimmingCharacters(in: .whitespacesAndNewlines))]
        }
    }

    private var records: some View {
        GeometryReader { geometry in
            HSplitView {
                List(model.records, selection: $selected) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind.isAudit ? record.auditTitle : record.title)
                            .font(.callout.weight(.medium)).lineLimit(2)
                        if kind.isAudit, let date = record.auditDate {
                            Text(date).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4).tag(record)
                }.frame(minWidth: 260, idealWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                recordDetails
                    .frame(minWidth: 320, idealWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    @ViewBuilder private var recordDetails: some View {
        if let selected {
            BusinessRecordDetail(account: account, kind: kind, record: selected) { Task { await load() } }
                .id(selected.id)
        } else {
            ContentUnavailableView("Select a Record", systemImage: "doc.text.magnifyingglass")
        }
    }

    private var collectionFooter: some View {
        VStack(spacing: 0) {
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
    }

    private func registerCommands() {
        commandContext.registerListActions(owner: commandOwner, actions: .init(
            primaryNew: kind.scim ? .init(title: kind == .provisioningUsers ? "New User…" : "New Group…",
                                          perform: { createPresented = true }) : nil,
            secondaryNew: nil, exportCSV: nil, exportSelectedCSV: nil,
            refresh: .init(title: "Reload", isEnabled: { !model.loading && (kind != .candidates || hasSearch) },
                           perform: { Task { await load() } })
        ))
    }

    private func load(more: Bool = false) async {
        if kind == .candidates, !hasSearch {
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
            NativeRecordContent(value: detail ?? record.value, style: kind.isAudit ? .audit : .general)
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
