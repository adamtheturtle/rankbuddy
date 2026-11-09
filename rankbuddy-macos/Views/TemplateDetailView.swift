//
//  TemplateDetailView.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

struct TemplateDetailView: View {
    let record: TemplateRecord
    let account: Account
    var onChanged: () -> Void = {}
    @State private var current: TemplateRecord?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editQuestionsPresented = false
    @State private var settingsPresented = false
    @State private var sharingPresented = false
    @State private var deletePresented = false
    @State private var deleted = false

    private var displayed: TemplateRecord {
        current ?? record
    }

    var body: some View {
        Form {
            if deleted {
                ContentUnavailableView("Template Deleted", systemImage: "trash")
            } else {
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
                        if let subject = displayed.subject,
                           !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(subject)
                        } else {
                            Text("No subject").foregroundStyle(.secondary)
                        }
                    }
                    Section("Email Body") {
                        if let content = displayed.content,
                           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            HTMLText(html: content)
                        } else {
                            Text("No email body").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .textSelection(.enabled)
        .task { await load() }
        .sheet(isPresented: $editQuestionsPresented, onDismiss: { Task { await load() } }, content: {
            TemplateQuestionsEditor(record: displayed, account: account) {
                current = $0
                onChanged()
            }
        })
        .sheet(isPresented: $settingsPresented) {
            TemplateEditorSheet(account: account, record: displayed) { changed() }
        }
        .sheet(isPresented: $sharingPresented) {
            if let id = displayed.apiID.flatMap(Int.init) {
                TemplateSharingSheet(account: account, templateID: id) { changed() }
            }
        }
        .confirmationDialog("Delete “\(displayed.title)”?", isPresented: $deletePresented, titleVisibility: .visible) {
            Button("Delete Template", role: .destructive) { Task { await delete() } }
        } message: { Text("The template will no longer be available for new interviews.") }
        .windowToolbar(id: "templateDetail") {
            if displayed.kind == .interview, !deleted {
                ToolbarItem(id: "templateActions", placement: .primaryAction) {
                    Menu("Template Actions", systemImage: "ellipsis.circle") {
                        Button("Template Settings…", systemImage: "slider.horizontal.3") { settingsPresented = true }
                        Button("Sharing…", systemImage: "person.badge.plus") { sharingPresented = true }
                        Button("Delete Template…", systemImage: "trash", role: .destructive) { deletePresented = true }
                    }
                    .disabled(isLoading || displayed.editorAccess != true || displayed.apiID.flatMap(Int.init) == nil)
                }
            }
            ToolbarItem(id: "refreshTemplate", placement: .primaryAction) {
                HStack {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    }
                    Button("Refresh Template", systemImage: "arrow.clockwise") {
                        Task { await load() }
                    }
                    .labelStyle(.iconOnly)
                    .help("Reload all details for the selected template")
                    .accessibilityIdentifier("refresh-template")
                    .disabled(isLoading || record.apiID == nil || deleted)
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

    private func changed() {
        onChanged()
        Task { await load() }
    }

    private func delete() async {
        guard let id = displayed.apiID.flatMap(Int.init), !isLoading else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await HackerRankClient(account: account).deleteInterviewTemplate(id: id)
            deleted = true
            onChanged()
        } catch { errorMessage = rankCoverageError(error) }
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
