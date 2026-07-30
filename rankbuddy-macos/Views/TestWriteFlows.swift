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

/// Whether the test editor is creating a new test or renaming an existing one (#57).
enum TestEditorMode {
    case create
    case edit(testID: String, currentName: String)
}

/// A sheet that creates a test (`POST /tests`) or renames one (`PATCH /tests/{id}`) (#57) —
/// a write flow. Refreshes the list on success.
struct TestEditorSheet: View {
    let account: Account
    let mode: TestEditorMode
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
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
        case let .edit(_, currentName):
            _name = State(initialValue: currentName)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedName: String {
        TestNameValidation.normalized(name)
    }

    private var currentName: String? {
        guard case let .edit(_, currentName) = mode else { return nil }

        return currentName
    }

    private var canSave: Bool {
        TestNameValidation.canSubmit(name, currentName: currentName)
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

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Rename Test" : "New Test")
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
        .frame(width: 440, height: 220)
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
                try await client.createTest(name: trimmedName)
            case let .edit(testID, _):
                try await client.updateTest(testID: testID, name: trimmedName)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("New Test (demo)") {
    TestEditorSheet(account: .demo, mode: .create) {}
}

#Preview("Rename (live)") {
    TestEditorSheet(
        account: Account(label: "Work", token: "live-token"),
        mode: .edit(testID: "t1", currentName: "Backend Screen")
    ) {}
}
