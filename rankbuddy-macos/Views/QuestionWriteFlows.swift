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
    @State private var mutationTask: Task<Void, Never>?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var payloadIssue: String? {
        QuestionAuthoringValidation.boundsIssue(
            problemStatement: problemStatement,
            languages: splitList(languages),
            tags: splitList(tags)
        )
    }

    private var displayedError: String? {
        errorMessage ?? payloadIssue
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

                if let displayedError {
                    Section {
                        Label(displayedError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Question")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        mutationTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Create") { mutationTask = Task { await create() } }
                            .disabled(trimmedName.isEmpty || payloadIssue != nil)
                            .help(trimmedName.isEmpty ? "Enter a name to create a question" : "Create question")
                    }
                }
            }
        }
        .frame(width: 460, height: displayedError == nil ? 460 : 540)
        .onDisappear { mutationTask?.cancel() }
    }

    private func create() async {
        if let payloadIssue {
            errorMessage = payloadIssue
            return
        }
        guard QuestionCreationValidation.isValidDurationText(duration) else {
            errorMessage = "Recommended duration must be a whole number of zero or more minutes."
            return
        }
        guard QuestionCreationValidation.isValidMaxScoreText(maxScore) else {
            errorMessage = "Max score must be a finite number of zero or greater."
            return
        }

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
                    recommendedDuration: QuestionCreationValidation.duration(from: duration),
                    tags: splitList(tags),
                    maxScore: QuestionCreationValidation.maxScore(from: maxScore)
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
    @State private var mutationTask: Task<Void, Never>?

    private var hasContent: Bool {
        TestcaseValidation.hasContent([name, input, output, score, explanation], isSample: isSample)
    }

    private var payloadIssue: String? {
        TestcaseValidation.boundsIssue(name: name, input: input, output: output, explanation: explanation)
    }

    private var displayedError: String? {
        errorMessage ?? payloadIssue
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

                if let displayedError {
                    Section {
                        Label(displayedError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Testcase")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        mutationTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Add") { mutationTask = Task { await add() } }
                            .disabled(!hasContent || payloadIssue != nil)
                    }
                }
            }
        }
        .frame(width: 460, height: displayedError == nil ? 520 : 600)
        .onDisappear { mutationTask?.cancel() }
    }

    private func add() async {
        if let payloadIssue {
            errorMessage = payloadIssue
            return
        }
        guard hasContent else {
            errorMessage = "Enter testcase content before adding it."
            return
        }
        guard TestcaseValidation.isValidScore(score) else {
            errorMessage = "Score must be a whole number of zero or greater."
            return
        }
        guard TestcaseValidation.isValidSample(isSample, input: input, output: output) else {
            errorMessage = "A sample testcase must include input or expected output."
            return
        }

        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            _ = try await HackerRankClient(account: account).addTestcase(
                questionID: questionID,
                options: QuestionTestcaseOptions(
                    explanation: nonBlank(explanation),
                    input: nonBlank(input),
                    output: nonBlank(output),
                    name: nonBlank(name),
                    sample: isSample,
                    score: Int(score.trimmingCharacters(in: .whitespacesAndNewlines))
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
    static let maxNameLength = 255
    static let maxDataLength = 1_000_000
    static let maxExplanationLength = 100_000

    static func hasContent(_ values: [String], isSample: Bool) -> Bool {
        values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } || isSample
    }

    static func isValidScore(_ score: String) -> Bool {
        let normalized = score.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty || Int(normalized).map { $0 >= 0 } == true
    }

    static func isValidSample(_ isSample: Bool, input: String, output: String) -> Bool {
        guard isSample else { return true }

        return [input, output].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func boundsIssue(name: String, input: String, output: String, explanation: String) -> String? {
        if name.count > maxNameLength {
            return "Testcase name must be at most 255 characters."
        }
        if input.count > maxDataLength {
            return "Testcase input must be at most 1,000,000 characters."
        }
        if output.count > maxDataLength {
            return "Expected output must be at most 1,000,000 characters."
        }
        if explanation.count > maxExplanationLength {
            return "Explanation must be at most 100,000 characters."
        }
        return nil
    }
}

nonisolated enum QuestionAuthoringValidation {
    static let maxProblemStatementLength = 1_000_000
    static let maxListCount = 100
    static let maxListItemLength = 255

    static func boundsIssue(problemStatement: String, languages: [String]?, tags: [String]?) -> String? {
        if problemStatement.count > maxProblemStatementLength {
            return "Problem statement must be at most 1,000,000 characters."
        }
        if let issue = listIssue(languages, label: "Languages") {
            return issue
        }
        if let issue = listIssue(tags, label: "Tags") {
            return issue
        }
        return nil
    }

    private static func listIssue(_ values: [String]?, label: String) -> String? {
        if let values, values.count > maxListCount {
            return "\(label) may contain at most 100 items."
        }
        if values?.contains(where: { $0.count > maxListItemLength }) == true {
            return "Each \(label.lowercased()) item must be at most 255 characters."
        }
        return nil
    }
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
