//
//  InterviewWriteFlows.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

/// A sheet that creates an instant QuickPad collaborative interview (`POST /interviews`,
/// #60) — a write flow. States plainly when it touches a real organisation, and refreshes
/// the list on success.
struct NewQuickPadSheet: View {
    let account: Account
    var onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title (optional)", text: $title)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.isMock
                            ? "Demo account: no real QuickPad is created."
                            : "This creates a real, ready-to-share QuickPad in your HackerRank organisation.")
                            .foregroundStyle(account.isMock ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))

                        if !account.isMock {
                            Text("Opens in your browser, which may be signed in to a different HackerRank account.")
                                .foregroundStyle(.secondary)
                        }
                    }
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
            .navigationTitle("New QuickPad")
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
            let created = try await HackerRankClient(account: account).createQuickPad(title: title)
            onCreated()
            if !account.isMock, let rawURL = created.url, let url = URL(string: rawURL) {
                BrowserSettings.open(url)
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// A sheet that schedules an interview (`POST /interviews`, #60). States plainly when it
/// touches a real organisation, and refreshes the list on success.
struct ScheduleInterviewSheet: View {
    let account: Account
    var onScheduled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var candidateEmail = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The form is valid with a title and, if a candidate email was entered, a plausible one.
    private var isValid: Bool {
        guard !trimmedTitle.isEmpty else { return false }

        let email = candidateEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty || EmailValidation.isLikelyValid(email)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Candidate email (optional)", text: $candidateEmail)
                        .textContentType(.emailAddress)
                        .disableAutocorrection(true)
                    DatePicker("Starts", selection: $date)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2 ... 4)
                } footer: {
                    Text(account.isMock
                        ? "Demo account: no real interview is scheduled."
                        : "This schedules a real interview in your HackerRank organisation.")
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
            .navigationTitle("Schedule Interview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Schedule") { Task { await schedule() } }
                            .disabled(!isValid)
                    }
                }
            }
        }
        .frame(width: 460, height: 380)
    }

    private func schedule() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await HackerRankClient(account: account).scheduleInterview(
                title: trimmedTitle,
                from: date,
                candidateEmail: candidateEmail,
                notes: notes
            )
            onScheduled()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("New QuickPad (demo)") {
    NewQuickPadSheet(account: .demo) {}
}

#Preview("Schedule (live)") {
    ScheduleInterviewSheet(account: Account(label: "Work", token: "live-token")) {}
}
