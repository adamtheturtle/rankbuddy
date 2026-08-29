//
//  TestWriteFlows.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

/// Whether the test editor is creating a new test or editing an existing assessment.
enum TestEditorMode {
    case create
    case edit(Test)
}

/// A sheet that creates or edits a test, including the assessment fields supported by
/// HackerRankKit's typed write options (#137).
struct TestEditorSheet: View {
    let account: Account
    let mode: TestEditorMode
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var duration: String
    @State private var cutoffScore: String
    @State private var instructions: String
    @State private var startTime: String
    @State private var endTime: String
    @State private var languages: String
    @State private var tags: String
    @State private var shuffleQuestions: Bool
    @State private var enableProctoring: Bool
    @State private var shuffleQuestionsChanged: Bool
    @State private var enableProctoringChanged: Bool
    @State private var roleIDs = ""
    @State private var experience = "Senior"
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var mutationTask: Task<Void, Never>?

    init(account: Account, mode: TestEditorMode, onSaved: @escaping () -> Void) {
        self.account = account
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _duration = State(initialValue: "")
            _cutoffScore = State(initialValue: "")
            _instructions = State(initialValue: "")
            _startTime = State(initialValue: "")
            _endTime = State(initialValue: "")
            _languages = State(initialValue: "")
            _tags = State(initialValue: "")
            _shuffleQuestions = State(initialValue: false)
            _enableProctoring = State(initialValue: false)
            _shuffleQuestionsChanged = State(initialValue: true)
            _enableProctoringChanged = State(initialValue: true)
            _roleIDs = State(initialValue: "")
            _experience = State(initialValue: "Senior")

        case let .edit(test):
            _name = State(initialValue: test.name)
            _duration = State(initialValue: test.duration.map(String.init) ?? "")
            _cutoffScore = State(initialValue: test.cutoffScore.map(String.init) ?? "")
            _instructions = State(initialValue: test.instructions ?? "")
            _startTime = State(initialValue: test.startTime ?? "")
            _endTime = State(initialValue: test.endTime ?? "")
            _languages = State(initialValue: test.languages?.joined(separator: ", ") ?? "")
            _tags = State(initialValue: test.tags?.joined(separator: ", ") ?? "")
            _shuffleQuestions = State(initialValue: test.shuffleQuestions ?? false)
            _enableProctoring = State(initialValue: test.enableProctoring ?? false)
            _shuffleQuestionsChanged = State(initialValue: false)
            _enableProctoringChanged = State(initialValue: false)
            _roleIDs = State(initialValue: test.roleIDs?.joined(separator: ", ") ?? "")
            _experience = State(initialValue: "")
        }
    }

    private var isEditing: Bool {
        if case .edit = mode {
            return true
        }
        return false
    }

    private var trimmedName: String {
        TestNameValidation.normalized(name)
    }

    private var canSave: Bool {
        TestNameValidation.isValid(trimmedName) && validationError == nil && createRequirementsMet
    }

    private var createRequirementsMet: Bool {
        guard !isEditing else { return true }

        let parsedDuration = Int(duration.trimmingCharacters(in: .whitespacesAndNewlines))
        let parsedRoleIDs = TestListEditing.values(from: roleIDs) ?? []
        let parsedExperience = TestListEditing.values(from: experience) ?? []
        return parsedDuration.map { $0 > 0 } == true
            && !parsedRoleIDs.isEmpty
            && !parsedExperience.isEmpty
    }

    private var options: TestWriteOptions {
        let duration = Int(duration.trimmingCharacters(in: .whitespacesAndNewlines))
        let cutoffScore = Int(cutoffScore.trimmingCharacters(in: .whitespacesAndNewlines))
        let languages = TestListEditing.values(from: languages)
        let tags = TestListEditing.values(from: tags)

        switch mode {
        case .create:
            return TestWriteOptions(
                duration: duration,
                cutoffScore: cutoffScore,
                instructions: instructions,
                startTime: startTime,
                endTime: endTime,
                languages: languages,
                tags: tags,
                shuffleQuestions: shuffleQuestions,
                enableProctoring: enableProctoring
            )

        case let .edit(test):
            return TestWriteOptions(
                duration: TestDirtyField.scalar(duration, original: test.duration),
                cutoffScore: TestDirtyField.scalar(cutoffScore, original: test.cutoffScore),
                instructions: TestDirtyField.text(instructions, original: test.instructions),
                startTime: TestDirtyField.text(startTime, original: test.startTime),
                endTime: TestDirtyField.text(endTime, original: test.endTime),
                languages: TestDirtyField.clearableList(languages, original: test.languages),
                tags: TestDirtyField.clearableList(tags, original: test.tags),
                shuffleQuestions: TestBooleanEditing.updateValue(
                    shuffleQuestions,
                    changed: shuffleQuestionsChanged
                ),
                enableProctoring: TestBooleanEditing.updateValue(
                    enableProctoring,
                    changed: enableProctoringChanged
                )
            )
        }
    }

    private var validationError: String? {
        if let error = TestAssessmentValidation.error(duration: duration, cutoffScore: cutoffScore) {
            return error
        }
        if !isEditing {
            if Int(duration.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
                return "Duration is required when creating a test."
            }
            if TestListEditing.values(from: roleIDs)?.isEmpty != false {
                return "At least one role id is required when creating a test."
            }
            if TestListEditing.values(from: experience)?.isEmpty != false {
                return "At least one experience level is required when creating a test."
            }
        }
        return TestScheduleValidation.error(startTime: startTime, endTime: endTime)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Test name", text: $name)
                } footer: {
                    if trimmedName.count > TestNameValidation.maxLength {
                        Text("Test name can be at most \(TestNameValidation.maxLength) characters.")
                            .foregroundStyle(.red)
                    }
                }

                Section("Assessment") {
                    TextField("Duration (minutes)", text: $duration)
                    TextField("Role ids (comma-separated)", text: $roleIDs, prompt: Text("Required when creating"))
                    TextField("Experience levels (comma-separated)", text: $experience, prompt: Text("e.g. Senior"))
                    TextField("Cutoff score", text: $cutoffScore)
                    TextField("Allowed languages (comma-separated)", text: $languages)
                    TextField("Tags (comma-separated)", text: $tags)
                    Toggle("Shuffle questions", isOn: $shuffleQuestions)
                        .onChange(of: shuffleQuestions) { _, _ in shuffleQuestionsChanged = true }
                    Toggle("Enable proctoring", isOn: $enableProctoring)
                        .onChange(of: enableProctoring) { _, _ in enableProctoringChanged = true }
                }

                Section("Schedule") {
                    TextField("Starts (ISO-8601)", text: $startTime)
                    TextField("Ends (ISO-8601)", text: $endTime)
                    if let validationError {
                        Text(validationError)
                            .foregroundStyle(.red)
                    }
                }

                Section("Candidate instructions") {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 90)
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
            .navigationTitle(isEditing ? "Edit Test" : "New Test")
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
                        Button(isEditing ? "Save" : "Create") {
                            mutationTask = Task { await save() }
                        }
                        .disabled(!canSave)
                    }
                }
            }
        }
        .frame(width: 520, height: 650)
        .interactiveDismissDisabled(isSending)
        .onDisappear { mutationTask?.cancel() }
    }
}

private extension TestEditorSheet {
    private func save() async {
        guard canSave else { return }

        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let client = HackerRankClient(account: account)
            switch mode {
            case .create:
                guard
                    let createDuration = Int(duration.trimmingCharacters(in: .whitespacesAndNewlines)),
                    let createRoleIDs = TestListEditing.values(from: roleIDs),
                    let createExperience = TestListEditing.values(from: experience)
                else { return }

                try await client.createTest(
                    name: trimmedName,
                    duration: createDuration,
                    roleIDs: createRoleIDs,
                    experience: createExperience,
                    options: options
                )

            case let .edit(test):
                let originalName = TestNameValidation.normalized(test.name)
                let shouldRebaseName = TestDirtyField.needsNameRebase(edited: trimmedName, original: originalName)
                let updateName: String = if shouldRebaseName {
                    try await latestTestName(testID: test.id, client: client)
                } else {
                    trimmedName
                }
                try await client.updateTest(testID: test.id, name: updateName, options: options)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func latestTestName(testID: String, client: HackerRankClient) async throws -> String {
        var cursor: String?
        var seen: Set<String> = []
        for _ in 0 ..< 100 {
            let page = try await client.testsPage(after: cursor)
            if let test = page.items.first(where: { $0.id == testID }) {
                return test.name
            }
            guard let next = page.next, seen.insert(next).inserted else { break }

            cursor = next
        }
        throw TestEditRebaseError.testNotFound
    }
}

nonisolated enum TestEditRebaseError: LocalizedError {
    case testNotFound

    var errorDescription: String? {
        "Couldn’t refresh this assessment before saving. Reload it and try again."
    }
}

nonisolated enum TestScheduleValidation {
    static func error(startTime: String, endTime: String) -> String? {
        let start = normalizedDate(startTime)
        let end = normalizedDate(endTime)
        if !startTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, start == nil {
            return "Start time must be an ISO-8601 timestamp."
        }
        if !endTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, end == nil {
            return "End time must be an ISO-8601 timestamp."
        }
        if let start, let end, end <= start {
            return "End time must be after start time."
        }
        return nil
    }

    private static func normalizedDate(_ value: String) -> Date? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }
}

#Preview("New Test (demo)") {
    TestEditorSheet(account: .demo, mode: .create) {}
}
