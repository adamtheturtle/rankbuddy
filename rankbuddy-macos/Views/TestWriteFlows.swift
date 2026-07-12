//
//  TestWriteFlows.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

/// Whether the test editor is creating a new test or renaming an existing one (#57).
enum TestEditorMode {
    case create
    case edit(testID: String, currentName: String)
}

/// A sheet that creates a test (`POST /tests`) or renames one (`PATCH /tests/{id}`) (#57) —
/// a write flow. States plainly when it touches a real organisation, and refreshes the list
/// on success.
struct TestEditorSheet: View {
    let account: Account
    let mode: TestEditorMode
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isSending = false
    @State private var errorMessage: String?

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
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Test name", text: $name)
                } footer: {
                    Text(consequenceText)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
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
                    Button("Cancel") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(isEditing ? "Save" : "Create") { Task { await save() } }
                            .disabled(trimmedName.isEmpty)
                    }
                }
            }
        }
        .frame(width: 440, height: 220)
    }

    private var consequenceText: String {
        isEditing
            ? "This renames a real test in your HackerRank organisation."
            : "This creates a real test in your HackerRank organisation."
    }

    private func save() async {
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
