//
//  NativeEntityPicker.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

extension EnvironmentValues {
    @Entry var nativeFeatureAccount: Account?
}

enum NativeEntityCollection: String {
    case tests, questions, users, teams, interviewTemplates, invitationTemplates

    init?(field: String) {
        switch field {
        case "template": self = .invitationTemplates
        case "test_id": self = .tests
        case "question_id", "question_ids", "questions", "qid": self = .questions
        case "user_id": self = .users
        case "team_id": self = .teams
        case "interview_template_id": self = .interviewTemplates
        default: return nil
        }
    }
}

struct NativePickerOption: Identifiable {
    let id: String
    let title: String
}

struct NativeEntityPicker: View {
    @Bindable var field: NativeFormField
    let collection: NativeEntityCollection
    let account: Account
    @State private var options: [NativePickerOption] = []
    @State private var cursor: String?
    @State private var loaded = false
    @State private var loading = false
    @State private var query = ""
    @State private var error: String?
    @State private var seenCursors = Set<String>()
    @State private var seenIDs = Set<String>()

    var body: some View {
        VStack(alignment: .leading) {
            if field.kind == "array" {
                TextField("Search loaded questions", text: $query)
                List(options.filter { query.isEmpty || $0.title.localizedStandardContains(query) }) { option in
                    Toggle(option.title, isOn: Binding(
                        get: { field.entries.contains { $0.text == option.id } },
                        set: { selected in
                            if selected {
                                field.addEntry()
                                field.entries.last?.text = option.id
                            } else {
                                field.entries.removeAll { $0.text == option.id }
                            }
                        }
                    ))
                }.frame(height: 180)
            } else {
                Picker(field.title, selection: $field.text) {
                    Text("Choose…").tag("")
                    if !field.text.isEmpty, !options.contains(where: { $0.id == field.text }) {
                        Text(field.text).tag(field.text)
                    }
                    ForEach(options) { Text($0.title).tag($0.id) }
                }
            }
            DisclosureGroup(field.kind == "array" ? "Use Question IDs" : "Use an ID") {
                if field.kind == "array" {
                    ForEach(field.entries) { entry in
                        TextField("Question ID", text: Binding(get: { entry.text }, set: { entry.text = $0 }))
                    }
                    Button("Add Question ID") { field.addEntry() }
                } else {
                    TextField("ID", text: $field.text)
                }
            }
            if !loaded || cursor != nil {
                Button("Load More") { Task { await load() } }.disabled(loading)
            }
            if loading {
                ProgressView().controlSize(.small)
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard !loading, !loaded || cursor != nil else { return }

        loading = true
        defer { loading = false }
        let client = HackerRankClient(account: account)
        do {
            let page: (options: [NativePickerOption], next: String?)
            switch collection {
            case .tests:
                let result = try await client.testsPage(after: cursor)
                page = (result.items.map { .init(id: $0.id, title: $0.name) }, result.next)

            case .questions:
                let result = try await client.questionsPage(after: cursor)
                page = (result.items.map { .init(id: $0.id, title: $0.name) }, result.next)

            case .users:
                let result = try await client.usersPage(after: cursor)
                page = (result.items.map { .init(id: $0.id, title: $0.email) }, result.next)

            case .teams:
                let result = try await client.teamsPage(after: cursor)
                page = (result.items.map { .init(id: $0.id, title: $0.name) }, result.next)

            case .invitationTemplates:
                let result = try await client.inviteTemplatesPage(after: cursor)
                page = (result.items.compactMap { template in
                    template.id.map { NativePickerOption(id: $0, title: template.name ?? $0) }
                }, result.next)

            case .interviewTemplates:
                let result = try await client.interviewTemplatesPage(after: cursor)
                page = (result.items.compactMap { value in
                    value.id.map { NativePickerOption(id: String($0), title: value.name ?? "Template \($0)") }
                }, result.next)
            }
            try Task.checkCancellation()
            let next = try InviteTemplatePaging.next(page.next, itemCount: page.options.count, seen: &seenCursors)
            InviteTemplatePaging.appendUnique(page.options, to: &options, seenIDs: &seenIDs, id: { $0.id })
            cursor = next
            loaded = true
        } catch {
            if !Task.isCancelled {
                self.error = rankCoverageError(error)
            }
        }
    }
}
