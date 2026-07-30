//
//  QuestionWriteFlows.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

/// The question types HackerRank accepts on create, shared by the create sheet's picker.
let questionTypes = ["coding", "mcq", "subjective"]

/// A sheet that creates a question (#147) — name and type are required (the API rejects a
/// create without them); everything else is optional metadata.
struct NewQuestionSheet: View {
    let account: Account
    var onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = "coding"
    @State private var problemStatement = ""
    @State private var duration = ""
    @State private var maxScore = ""
    @State private var languages = ""
    @State private var tags = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(questionTypes, id: \.self) { Text(DisplayFormat.enumLabel($0)).tag($0) }
                    }
                    TextField("Recommended duration (minutes)", text: $duration)
                    TextField("Max score", text: $maxScore)
                    TextField("Languages", text: $languages, prompt: Text("Comma-separated, e.g. python, java"))
                    TextField("Tags", text: $tags, prompt: Text("Comma-separated"))
                }

                Section("Problem statement") {
                    TextField("Problem statement", text: $problemStatement, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(4 ... 12)
                        .labelsHidden()
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
            .navigationTitle("New Question")
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
                            .disabled(trimmedName.isEmpty)
                            .help(trimmedName.isEmpty ? "Enter a name to create a question" : "Create question")
                    }
                }
            }
        }
        .frame(width: 460, height: errorMessage == nil ? 460 : 540)
    }

    private func create() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            _ = try await HackerRankClient(account: account).createQuestion(
                name: trimmedName,
                type: type,
                options: QuestionWriteOptions(
                    languages: splitList(languages),
                    problemStatement: nonBlank(problemStatement),
                    recommendedDuration: Int(duration.trimmingCharacters(in: .whitespaces)),
                    tags: splitList(tags),
                    maxScore: Double(maxScore.trimmingCharacters(in: .whitespaces))
                )
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// A sheet that adds a testcase to a coding question (#147). HackerRank has no testcase
/// *read* endpoint, so the app can add and bulk-delete testcases but not list them.
struct AddTestcaseSheet: View {
    let questionID: String
    let account: Account
    var onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var input = ""
    @State private var output = ""
    @State private var score = ""
    @State private var isSample = false
    @State private var explanation = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var hasContent: Bool {
        TestcaseValidation.hasContent([name, input, output, score, explanation], isSample: isSample)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Optional"))
                    TextField("Score", text: $score, prompt: Text("Optional"))
                    Toggle("Sample (shown to candidates)", isOn: $isSample)
                }

                Section("Input") {
                    TextField("Input", text: $input, axis: .vertical)
                        .lineLimit(3 ... 8)
                        .labelsHidden()
                        .font(.body.monospaced())
                }

                Section("Expected output") {
                    TextField("Expected output", text: $output, axis: .vertical)
                        .lineLimit(3 ... 8)
                        .labelsHidden()
                        .font(.body.monospaced())
                }

                Section("Explanation") {
                    TextField("Explanation", text: $explanation, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(2 ... 6)
                        .labelsHidden()
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
            .navigationTitle("Add Testcase")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Add") { Task { await add() } }
                            .disabled(!hasContent)
                    }
                }
            }
        }
        .frame(width: 460, height: errorMessage == nil ? 520 : 600)
    }

    private func add() async {
        guard hasContent else {
            errorMessage = "Enter testcase content before adding it."
            return
        }

        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            _ = try await HackerRankClient(account: account).addTestcase(
                questionID: questionID,
                body: TestcaseBody(
                    name: nonBlank(name),
                    input: nonBlank(input),
                    output: nonBlank(output),
                    score: Int(score.trimmingCharacters(in: .whitespaces)),
                    sample: isSample,
                    explanation: nonBlank(explanation)
                )
            )
            onAdded()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Request bodies

nonisolated enum TestcaseValidation {
    static func hasContent(_ values: [String], isSample: Bool) -> Bool {
        values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } || isSample
    }
}

// These mirror HackerRankKit's typed requests (which land in a future Kit release); Kit
// 0.4.0's testcase/codestub endpoints accept any `Encodable` body. Synthesized encoding
// omits `nil` fields, so only the fields the user filled in are sent.

/// The body for `POST /questions/{id}/testcases`.
nonisolated struct TestcaseBody: Encodable {
    var name: String?
    var input: String?
    var output: String?
    var score: Int?
    var sample: Bool?
    var explanation: String?
}

// MARK: - Shared field helpers

// Internal (not private) because the code-stub sheets in
// QuestionCodeStubSheets.swift share them.

/// "a, b, c" → ["a", "b", "c"]; nil when the field is blank.
func splitList(_ text: String) -> [String]? {
    var seen: Set<String> = []
    let parts = text.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .filter {
            let key = $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted
        }
    return parts.isEmpty ? nil : parts
}

/// Trims a free-text field; nil when it is blank so the request omits it.
func nonBlank(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
