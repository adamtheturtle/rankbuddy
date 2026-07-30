//
//  TestWriteFlows.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

nonisolated enum TestNameValidation {
    static let maxLength = 255

    static func isValid(_ name: String) -> Bool {
        !name.isEmpty && name.count <= maxLength
    }

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canSubmit(_ name: String, currentName: String?) -> Bool {
        let normalizedName = normalized(name)
        guard isValid(normalizedName) else { return false }

        return currentName.map(normalized) != normalizedName
    }
}

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
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedName: String {
        TestNameValidation.normalized(name)
    }

    private var canSave: Bool {
        TestNameValidation.isValid(trimmedName) && validationError == nil
    }

    private var options: TestWriteOptions {
        TestWriteOptions(
            duration: Int(duration),
            cutoffScore: Int(cutoffScore),
            instructions: instructions,
            startTime: startTime,
            endTime: endTime,
            languages: commaSeparated(languages),
            tags: commaSeparated(tags),
            shuffleQuestions: shuffleQuestions,
            enableProctoring: enableProctoring
        )
    }

    private var validationError: String? {
        if !duration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Int(duration).map({ $0 > 0 }) != true {
            return "Duration must be a whole number greater than zero."
        }
        if !cutoffScore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Int(cutoffScore).map({ $0 >= 0 }) != true {
            return "Cutoff score must be a whole number of zero or more."
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
                    TextField("Cutoff score", text: $cutoffScore)
                    TextField("Allowed languages (comma-separated)", text: $languages)
                    TextField("Tags (comma-separated)", text: $tags)
                    Toggle("Shuffle questions", isOn: $shuffleQuestions)
                    Toggle("Enable proctoring", isOn: $enableProctoring)
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

    private func save() async {
        guard canSave else { return }

        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let client = HackerRankClient(account: account)
            switch mode {
            case .create:
                try await client.createTest(name: trimmedName, options: options)
            case let .edit(test):
                try await client.updateTest(testID: test.id, name: trimmedName, options: options)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func commaSeparated(_ value: String) -> [String]? {
        let values = value.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
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
        if let start, let end, end < start {
            return "End time must not be before start time."
        }
        return nil
    }

    private static func normalizedDate(_ value: String) -> Date? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : ISO8601DateFormatter().date(from: value)
    }
}

#Preview("New Test (demo)") {
    TestEditorSheet(account: .demo, mode: .create) {}
}
