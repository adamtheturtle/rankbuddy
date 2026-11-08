//
//  TemplateQuestionsEditor.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

struct TemplateQuestionsEditor: View {
    let account: Account
    let onChanged: (TemplateRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var model: TemplateQuestionEditorModel

    init(record: TemplateRecord, account: Account, onChanged: @escaping (TemplateRecord) -> Void) {
        self.account = account
        self.onChanged = onChanged
        _model = State(initialValue: TemplateQuestionEditorModel(
            record: record, client: HackerRankClient(account: account)
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Questions").font(.title2).bold()
            Text(model.record.title).foregroundStyle(.secondary)
            if let error = model.errorMessage {
                HStack {
                    Text(error).foregroundStyle(.red)
                    Button("Refresh") { Task { await model.refresh() } }
                        .disabled(model.isSaving)
                }
            }
            HSplitView {
                membership.frame(minWidth: 280)
                library.frame(minWidth: 320)
            }
            HStack {
                if model.isSaving {
                    ProgressView().controlSize(.small)
                }
                Text("Changes are saved immediately.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    onChanged(model.record)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isSaving)
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 540)
        .interactiveDismissDisabled(model.isSaving)
        .task {
            await model.refresh()
            await model.loadMore()
        }
        .task(id: model.query) {
            guard !model.query.isEmpty else { return }

            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            await model.searchMore()
        }
    }

    private var membership: some View {
        VStack(alignment: .leading) {
            Text("In This Template").font(.headline)
            List {
                ForEach(Array((model.record.questionIDs ?? []).enumerated()), id: \.offset) { _, id in
                    HStack {
                        TemplateQuestionRow(questionID: id, account: account)
                        Button("Remove from Template", systemImage: "minus.circle") {
                            Task { await model.remove(id) }
                        }
                        .labelStyle(.iconOnly)
                        .help("Remove this question from the template")
                        .disabled(!model.canEdit)
                    }
                }
            }
            Text("\(model.record.questionIDs?.count ?? 0) questions").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var library: some View {
        VStack(alignment: .leading) {
            Text("Question Library").font(.headline)
            TextField("Search questions", text: $model.query)
                .textFieldStyle(.roundedBorder)
            List(model.candidates) { question in
                HStack {
                    VStack(alignment: .leading) {
                        Text(question.name)
                        Text(question.type).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add", systemImage: "plus.circle") { Task { await model.add(question) } }
                        .disabled(!model.canEdit || Int(question.id) == nil)
                }
            }
            HStack {
                if model.isLoading {
                    ProgressView().controlSize(.small)
                }
                if !model.didLoadQuestions || model.nextCursor != nil {
                    Button(model.query.isEmpty ? "Load More Questions" : "Search More Questions") {
                        Task { await model.loadMore() }
                    }
                    .disabled(model.isLoading)
                }
                Spacer()
            }
        }
    }
}
