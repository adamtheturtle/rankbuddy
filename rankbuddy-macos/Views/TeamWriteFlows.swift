//
//  TeamWriteFlows.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

/// A sheet that creates a team (`POST /teams`, #59) — a write flow. States plainly when it
/// touches a real organisation, and refreshes the list on success.
struct CreateTeamSheet: View {
    let account: Account
    var onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Team name", text: $name)
                } footer: {
                    Text(account.isMock
                        ? "Demo account: no real team is created."
                        : "This creates a real team in your HackerRank for Work organisation.")
                        .foregroundStyle(account.isMock ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
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
            .navigationTitle("New Team")
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
                    }
                }
            }
        }
        .frame(width: 440, height: 240)
    }

    private func create() async {
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

/// A sheet that adds a member to a team (`POST /teams/{id}/users`, #59). States plainly when
/// it touches a real organisation, and refreshes the members list on success.
struct AddTeamMemberSheet: View {
    let teamID: String
    let account: Account
    var onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var role = "interviewer"
    @State private var isSending = false
    @State private var errorMessage: String?

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
                        ForEach(Self.roles, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                } footer: {
                    Text(account.isMock
                        ? "Demo account: no real member is added."
                        : "This adds a real member to the team on HackerRank.")
                        .foregroundStyle(account.isMock ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
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
            .navigationTitle("Add Member")
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
                            .disabled(!EmailValidation.isLikelyValid(email))
                    }
                }
            }
        }
        .frame(width: 440, height: 280)
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
