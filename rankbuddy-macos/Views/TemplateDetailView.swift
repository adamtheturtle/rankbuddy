//
//  TemplateDetailView.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

struct TemplateDetailView: View {
    let record: TemplateRecord
    let account: Account
    @State private var current: TemplateRecord?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editQuestionsPresented = false

    private var displayed: TemplateRecord {
        current ?? record
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayed.title).font(.title2).bold()
                    Text(account.label).foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                    Button("Retry") { Task { await load() } }
                }
            }
            if displayed.kind == .interview {
                questions
            }
            Section("Properties") {
                OptionalRow("ID", displayed.apiID)
                OptionalRow("Owner ID", displayed.owner)
                OptionalRow("Created", DisplayFormat.date(displayed.createdAt))
                if displayed.kind == .interview {
                    OptionalRow("Status", displayed.status.map {
                        $0 == 1 ? "Active" : $0 == 0 ? "Deleted" : String($0)
                    })
                    OptionalRow("Role IDs", displayed.roles?.joined(separator: ", "))
                    OptionalRow("Scorecard ID", displayed.scorecard.map(String.init))
                    OptionalRow("Edit Access", displayed.editorAccess.map { $0 ? "Yes" : "No" })
                    OptionalRow("Import Available", displayed.importTemplate.map { $0 ? "Yes" : "No" })
                } else {
                    OptionalRow("Updated", DisplayFormat.date(displayed.updatedAt))
                    OptionalRow("Default Template", displayed.isDefault.map { $0 ? "Yes" : "No" })
                }
            }
            if displayed.kind == .invitation {
                Section("Subject") {
                    Text(displayed.subject ?? "No subject")
                }
                Section("Email Body") {
                    if let content = displayed.content, !content.isEmpty {
                        HTMLText(html: content)
                    } else {
                        Text("No email body").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .textSelection(.enabled)
        .task { await load() }
        .sheet(isPresented: $editQuestionsPresented, onDismiss: { Task { await load() } }, content: {
            TemplateQuestionsEditor(record: displayed, account: account) { current = $0 }
        })
        .toolbar(id: "templateDetail") {
            ToolbarItem(id: "refreshTemplate", placement: .primaryAction) {
                HStack {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    }
                    Button("Refresh Template", systemImage: "arrow.clockwise") {
                        Task { await load() }
                    }
                    .labelStyle(.titleAndIcon)
                    .help("Reload all details for the selected template")
                    .accessibilityIdentifier("refresh-template")
                    .disabled(isLoading || record.apiID == nil)
                }
            }
        }
    }

    private var questions: some View {
        Section {
            if let ids = displayed.questionIDs {
                if ids.isEmpty {
                    Text("No questions in this template").foregroundStyle(.secondary)
                } else {
                    Text("\(ids.count) \(ids.count == 1 ? "question" : "questions")").foregroundStyle(.secondary)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(ids.enumerated()), id: \.offset) { _, id in
                                TemplateQuestionRow(questionID: id, account: account)
                            }
                        }
                    }
                    .frame(height: min(CGFloat(ids.count) * 40, 360))
                }
            } else {
                Text(isLoading ? "Loading question membership…" : "Question membership was not returned.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Questions")
                Spacer()
                Button("Edit Questions", systemImage: "pencil") { editQuestionsPresented = true }
                    .disabled(isLoading || displayed.editorAccess != true || displayed.apiID.flatMap(Int.init) == nil)
                    .help(displayed.editorAccess == false ? "This template is read-only" : "Add or remove questions")
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let detail = try await TemplateLibrary.detail(record, client: HackerRankClient(account: account))
            try Task.checkCancellation()
            current = detail
        } catch {
            guard !Task.isCancelled else { return }

            errorMessage = rankCoverageError(error)
        }
    }
}

struct TemplateQuestionRow: View {
    let questionID: String
    let account: Account
    @Environment(\.openWindow) private var openWindow
    @State private var question: Question?
    @State private var failed = false

    var body: some View {
        HStack {
            Button {
                if let question {
                    openWindow(value: DetailWindowValue.question(question, accountID: account.id))
                }
            } label: {
                Label(question?.name ?? "Question \(questionID)", systemImage: "questionmark.bubble")
            }
            .buttonStyle(.link)
            .disabled(question == nil)
            Spacer()
            if failed {
                Button("Retry") { Task { await load() } }
                    .help("Couldn’t load question \(questionID)")
            } else if question == nil {
                ProgressView().controlSize(.small)
            }
        }
        .task { await load() }
    }

    private func load() async {
        failed = false
        do {
            let result = try await TemplateLibrary.question(id: questionID, client: HackerRankClient(account: account))
            try Task.checkCancellation()
            question = result
        } catch {
            guard !Task.isCancelled else { return }

            failed = true
        }
    }
}
