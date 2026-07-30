//
//  TeamWriteFlows.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

nonisolated enum TeamNameValidation {
    static let maxLength = 255

    static func isValid(_ name: String) -> Bool {
        !name.isEmpty && name.count <= maxLength
    }
}

/// A sheet that creates a team (`POST /teams`, #59) — a write flow. Refreshes the list on success.
struct CreateTeamSheet: View {
    let account: Account
    var onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var mutationTask: Task<Void, Never>?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Team name", text: $name)
                } footer: {
                    if trimmedName.count > TeamNameValidation.maxLength {
                        Text("Team name can be at most \(TeamNameValidation.maxLength) characters.")
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
            .navigationTitle("New Team")
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
                            .disabled(!TeamNameValidation.isValid(trimmedName))
                    }
                }
            }
        }
        .frame(width: 440, height: 240)
        .onDisappear { mutationTask?.cancel() }
    }

    private func create() async {
        guard TeamNameValidation.isValid(trimmedName) else { return }

        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await HackerRankClient(account: account).createTeam(name: trimmedName)
            onCreated()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// A sheet that adds a member to a team (`POST /teams/{id}/users`, #59). Refreshes the
/// members list on success.
struct AddTeamMemberSheet: View {
    let teamID: String
    let account: Account
    var onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var role = "interviewer"
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var mutationTask: Task<Void, Never>?

    private static let roles = ["recruiter", "interviewer", "developer"]

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .disableAutocorrection(true)
                    Picker("Role", selection: $role) {
                        ForEach(Self.roles, id: \.self) { Text(DisplayFormat.enumLabel($0)).tag($0) }
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
            .navigationTitle("Add Member")
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
                            .disabled(!EmailValidation.isLikelyValid(email))
                    }
                }
            }
        }
        .frame(width: 440, height: 280)
        .onDisappear { mutationTask?.cancel() }
    }

    private func add() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await HackerRankClient(account: account).addTeamMember(teamID: teamID, email: trimmedEmail, role: role)
            onAdded()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("New Team (demo)") {
    CreateTeamSheet(account: .demo) {}
}

#Preview("Add Member (live)") {
    AddTeamMemberSheet(teamID: "tm1", account: Account(label: "Work", token: "live-token")) {}
}
