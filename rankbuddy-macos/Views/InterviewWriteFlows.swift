//
//  InterviewWriteFlows.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

struct MissingPadURL: LocalizedError {
    var errorDescription: String? {
        "HackerRank created the Pad but did not return a valid web URL. Try again or find it in Interviews."
    }
}

nonisolated func padDestinationURL(rawURL: String?, isMock: Bool) throws -> URL? {
    if isMock {
        return nil
    }
    guard let rawURL, let url = URL.remoteWebURL(from: rawURL) else {
        throw MissingPadURL()
    }

    return url
}

nonisolated enum PadTitleValidation {
    static let maxLength = 255

    static func normalized(_ title: String?) -> String? {
        guard let title else { return nil }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return String(trimmed.prefix(maxLength))
    }
}

nonisolated enum InterviewScheduleValidation {
    static let maxTitleLength = 255
    static let maxEmailLength = 320
    static let maxNotesLength = 10000

    static func titleIssue(_ title: String) -> String? {
        title.count > maxTitleLength ? "Title can be at most \(maxTitleLength) characters." : nil
    }

    static func notesIssue(_ notes: String?) -> String? {
        guard let notes, notes.count > maxNotesLength else { return nil }

        return "Notes can be at most \(maxNotesLength.formatted()) characters."
    }

    static func textIssue(title: String, candidateEmail: String?, notes: String?) -> String? {
        if let issue = titleIssue(title) {
            return issue
        }
        if let candidateEmail, candidateEmail.count > maxEmailLength {
            return "Candidate email can be at most \(maxEmailLength) characters."
        }
        if let issue = notesIssue(notes) {
            return issue
        }
        return nil
    }

    static func dateIssue(start: Date, now: Date = Date()) -> String? {
        start > now ? nil : "Start time must be in the future."
    }
}

/// A sheet that creates an instant collaborative Pad interview (`POST /interviews`,
/// #60) — a write flow. Refreshes the list on success.
struct NewPadSheet: View {
    let account: Account
    var onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var mutationTask: Task<Void, Never>?

    /// The optional request field, normalized separately from the editable UI value so blank
    /// whitespace is omitted rather than sent as an explicit title.
    private var requestTitle: String? {
        PadTitleValidation.normalized(title)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title (optional)", text: $title)
                } footer: {
                    if title.count > PadTitleValidation.maxLength {
                        Text("Titles can be at most \(PadTitleValidation.maxLength) characters.")
                            .foregroundStyle(.red)
                    } else if !account.isMock {
                        Text("Opens in your browser, which may be signed in to a different HackerRank account.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
            .navigationTitle("New Pad")
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
                            .disabled(title.count > PadTitleValidation.maxLength)
                    }
                }
            }
        }
        .frame(width: 440, height: 240)
        .interactiveDismissDisabled(isSending)
        .onDisappear { mutationTask?.cancel() }
    }

    private func create() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let created = try await HackerRankClient(account: account)
                .createPad(title: requestTitle)
            onCreated()
            // Creation is already committed at this point. A missing/invalid navigation URL must
            // not leave the sheet offering a duplicate-producing retry.
            let destination = try? padDestinationURL(rawURL: created.url, isMock: account.isMock)
            if let destination {
                BrowserSettings.open(destination)
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// A sheet that schedules an interview (`POST /interviews`, #60). Refreshes the list on success.
struct ScheduleInterviewSheet: View {
    let account: Account
    var onScheduled: () -> Void
    var body: some View {
        NativeFeatureFormSheet(title: "Schedule Interview", operationID: "api_create_interview", account: account,
                               onSaved: onScheduled)
    }
}
