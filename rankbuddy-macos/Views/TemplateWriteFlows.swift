//
//  TemplateWriteFlows.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

struct TemplateEditorSheet: View {
    let account: Account
    var record: TemplateRecord?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var roleID = ""
    @State private var scorecardID = ""
    @State private var questions: [Question] = []
    @State private var selected = Set<String>()
    @State private var query = ""
    @State private var cursor: String?
    @State private var loaded = false
    @State private var loading = false
    @State private var saving = false
    @State private var uncertain = false
    @State private var error: String?

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (scorecardID.isEmpty || Int(scorecardID) != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Account", value: account.label)
                    TextField("Name", text: $name)
                    TextField("Role ID (optional)", text: $roleID)
                    if record != nil {
                        TextField("Scorecard ID (optional)", text: $scorecardID)
                    }
                }
                if record == nil {
                    Section("Questions") {
                        TextField("Search loaded questions", text: $query)
                        List(questions
                            .filter { query.isEmpty || $0.name.localizedStandardContains(query) }) { question in
                                Toggle(question.name, isOn: Binding(
                                    get: { selected.contains(question.id) },
                                    set: {
                                        if $0 {
                                            selected.insert(question.id)
                                        } else {
                                            selected.remove(question.id)
                                        }
                                    }
                                ))
                                .disabled(Int(question.id) == nil)
                            }
                            .frame(height: 210)
                        HStack {
                            Text("\(selected.count) selected").foregroundStyle(.secondary)
                            Spacer()
                            if !loaded || cursor != nil {
                                Button("Load More Questions") { Task { await loadQuestions() } }.disabled(loading)
                            }
                            if loading {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(record == nil ? "New Template" : "Template Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(record == nil ? "Create" : "Save") { Task { await save() } }
                        .disabled(!valid || saving || uncertain)
                }
            }
        }
        .frame(width: 620, height: record == nil ? 550 : 280)
        .interactiveDismissDisabled(saving)
        .task {
            name = record?.title ?? ""
            roleID = record?.roles?.first ?? ""
            scorecardID = record?.scorecard.map(String.init) ?? ""
            if record == nil {
                await loadQuestions()
            }
        }
    }

    private func loadQuestions() async {
        guard !loading else { return }

        loading = true
        defer { loading = false }
        do {
            guard let page = try await ListPageLoading.load({
                try await HackerRankClient(account: account).questionsPage(after: cursor)
            }) else { return }

            questions = ListPageMerge.merge(questions, with: page.items)
            cursor = page.next
            loaded = true
            error = nil
        } catch { self.error = rankCoverageError(error) }
    }

    private func save() async {
        guard valid, !saving else { return }

        saving = true
        defer { saving = false }
        do {
            let client = HackerRankClient(account: account)
            if let record, let id = record.apiID.flatMap(Int.init) {
                _ = try await client.updateInterviewTemplate(id: id, options: .init(
                    name: name == record.title ? nil : name,
                    roleID: roleID == record.roles?.first ? nil : roleID,
                    scorecardID: scorecardID == record.scorecard.map(String.init) ? nil : Int(scorecardID)
                ))
            } else {
                _ = try await client.createInterviewTemplate(name: name, options: .init(
                    roleID: roleID, questionIDs: selected.sorted().compactMap(Int.init)
                ))
            }
            onSaved()
            dismiss()
        } catch {
            uncertain = NativeWriteFailure.mightHaveCommitted(error)
            self.error = uncertain ? NativeWriteFailure.message
                : rankCoverageError(error)
            if uncertain {
                onSaved()
            }
        }
    }
}

struct TemplateSharingSheet: View {
    let account: Account
    let templateID: Int
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "user"
    @State private var targetID = ""
    @State private var role = InterviewTemplateShareRole.viewer
    @State private var revoke = false
    @State private var people: [User] = []
    @State private var teams: [Team] = []
    @State private var cursor: String?
    @State private var loading = false
    @State private var saving = false
    @State private var uncertain = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Account", value: account.label)
                Picker("Share with", selection: $kind) {
                    Text("Person").tag("user")
                    Text("Team").tag("team")
                    Text("Everyone in the organisation").tag("company")
                }
                if kind != "company" {
                    Picker(kind == "user" ? "Person" : "Team", selection: $targetID) {
                        Text("Choose…").tag("")
                        if kind == "user" {
                            ForEach(people) { Text($0.email).tag($0.id) }
                        } else {
                            ForEach(teams) { Text($0.name).tag($0.id) }
                        }
                    }
                    if cursor != nil {
                        Button("Load More") { Task { await load(reset: false) } }.disabled(loading)
                    }
                }
                Toggle("Remove access", isOn: $revoke)
                if !revoke {
                    Picker("Access", selection: $role) {
                        Text("Can view").tag(InterviewTemplateShareRole.viewer)
                        Text("Can edit").tag(InterviewTemplateShareRole.editor)
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                if loading || saving {
                    ProgressView().controlSize(.small)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Template Sharing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(revoke ? "Remove Access" : "Share") { Task { await save() } }
                        .disabled(saving || uncertain || (kind != "company" && targetID.isEmpty))
                }
            }
        }
        .frame(width: 520, height: 360)
        .interactiveDismissDisabled(saving)
        .task(id: kind) { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        if reset {
            targetID = ""; cursor = nil; people = []; teams = []
        }
        guard kind != "company" else { return }

        loading = true
        defer { loading = false }
        let selectedKind = kind
        do {
            let client = HackerRankClient(account: account)
            if kind == "user" {
                let page = try await client.usersPage(after: cursor)
                try Task.checkCancellation()
                guard kind == selectedKind else { return }

                people = ListPageMerge.merge(people, with: page.items)
                cursor = page.next
            } else {
                let page = try await client.teamsPage(after: cursor)
                try Task.checkCancellation()
                guard kind == selectedKind else { return }

                teams = ListPageMerge.merge(teams, with: page.items)
                cursor = page.next
            }
        } catch {
            if !Task.isCancelled {
                self.error = rankCoverageError(error)
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let target: InterviewTemplateShareTarget = kind == "company" ? .company
                : kind == "team" ? .team(id: targetID) : .user(id: targetID)
            let client = HackerRankClient(account: account)
            let result: InterviewTemplateSharingResult = if revoke {
                try await client.unshareInterviewTemplate(id: templateID, from: [target])
            } else {
                try await client.shareInterviewTemplate(id: templateID, grants: [.init(target: target, role: role)])
            }
            if result.status == false {
                throw NativeFormError.invalid(result.message ?? "HackerRank did not apply the sharing change.")
            }
            onSaved()
            dismiss()
        } catch {
            uncertain = NativeWriteFailure.mightHaveCommitted(error)
            self.error = uncertain ? NativeWriteFailure.message
                : rankCoverageError(error)
            if uncertain {
                onSaved()
            }
        }
    }
}
