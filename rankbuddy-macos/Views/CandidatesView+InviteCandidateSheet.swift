//
//  CandidatesView+InviteCandidateSheet.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit
import SwiftUI

/// Product/API guardrails shared by the invite sheet and non-UI write surfaces.
enum CandidateInviteValidation {
    struct TextFields {
        var fullName: String?
        var tags: [String]?
        var evaluatorEmail: String?
        var emailSubject: String?
        var emailMessage: String?
        var atsCandidateID: String?
        var atsRequisitionID: String?
    }

    /// One day is a generous accommodation ceiling while preventing accidental pasted magnitudes.
    static let additionalTimeRange = 0 ... 1440
    static let maxFullNameLength = 255
    static let maxTagLength = 100
    static let maxTagCount = 50
    static let maxEmailLength = 320
    static let maxIdentifierLength = 255
    static let maxSubjectLength = 255
    static let maxMessageLength = 10000

    static func isValid(additionalTime: Int?) -> Bool {
        additionalTime.map(additionalTimeRange.contains) ?? true
    }

    static func validityOrderIssue(validFrom: String?, validUntil: String?) -> String? {
        guard
            let validFrom,
            let validUntil,
            let start = parsedTimestamp(validFrom),
            let end = parsedTimestamp(validUntil),
            end <= start
        else {
            return nil
        }

        return "Valid until must be later than Valid from."
    }

    static func validityTimestampIssue(validFrom: String?, validUntil: String?) -> String? {
        if let validFrom, parsedTimestamp(validFrom) == nil {
            return "Valid from must be an ISO-8601 timestamp."
        }
        if let validUntil, parsedTimestamp(validUntil) == nil {
            return "Valid until must be an ISO-8601 timestamp."
        }
        return nil
    }

    static func normalizedFullName(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedTags(_ value: String) -> [String]? {
        var seen: Set<String> = []
        let tags = value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(ListQuery.normalizedFacetValue($0)).inserted }
        return tags.isEmpty ? nil : tags
    }

    static func textIssue(_ fields: TextFields) -> String? {
        if let fullName = fields.fullName, fullName.count > maxFullNameLength {
            return "Full name can be at most \(maxFullNameLength) characters."
        }
        if let tags = fields.tags, tags.count > maxTagCount {
            return "Use at most \(maxTagCount) tags."
        }
        if let tag = fields.tags?.first(where: { $0.count > maxTagLength }) {
            return "Tag “\(tag.prefix(20))” exceeds \(maxTagLength) characters."
        }
        if let evaluatorEmail = fields.evaluatorEmail, evaluatorEmail.count > maxEmailLength {
            return "Evaluator email can be at most \(maxEmailLength) characters."
        }
        if let emailSubject = fields.emailSubject, emailSubject.count > maxSubjectLength {
            return "Email subject can be at most \(maxSubjectLength) characters."
        }
        if let emailMessage = fields.emailMessage, emailMessage.count > maxMessageLength {
            return "Email message can be at most \(maxMessageLength.formatted()) characters."
        }
        if let atsCandidateID = fields.atsCandidateID, atsCandidateID.count > maxIdentifierLength {
            return "ATS candidate ID can be at most \(maxIdentifierLength) characters."
        }
        if let atsRequisitionID = fields.atsRequisitionID, atsRequisitionID.count > maxIdentifierLength {
            return "ATS requisition ID can be at most \(maxIdentifierLength) characters."
        }
        return nil
    }

    private static func parsedTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }
}

/// A sheet that invites a candidate to a test (#12) — the app's first write flow. Refreshes
/// the list on success.
struct InviteCandidateSheet: View {
    let testID: String
    let account: Account
    /// Called after a successful invite so the caller can refresh the candidates list.
    var onInvited: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var fullName = ""
    @State private var sendEmail = true
    @State private var additionalTime = ""
    @State private var validFrom = ""
    @State private var validUntil = ""
    @State private var emailSubject = ""
    @State private var emailMessage = ""
    @State private var evaluatorEmail = ""
    @State private var tags = ""
    @State private var atsCandidateID = ""
    @State private var atsRequisitionID = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var mutationTask: Task<Void, Never>?
    /// The account's invitation email templates (#147); the picker is hidden when none load.
    @State private var templates: [InviteTemplate] = []
    @State private var selectedTemplateID: String?

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEmailValid: Bool {
        EmailValidation.isLikelyValid(email)
    }

    private var evaluatorEmailValid: Bool {
        trimmed(evaluatorEmail).map(EmailValidation.isLikelyValid) ?? true
    }

    private var additionalTimeMinutes: Int? {
        trimmed(additionalTime).flatMap(Int.init)
    }

    private var additionalTimeValid: Bool {
        trimmed(additionalTime) == nil
            || additionalTimeMinutes.map(CandidateInviteValidation.additionalTimeRange.contains) == true
    }

    private var canInvite: Bool {
        isEmailValid
            && evaluatorEmailValid
            && additionalTimeValid
            && validityTimestampIssue == nil
            && validityOrderIssue == nil
            && textValidationIssue == nil
    }

    private var validityTimestampIssue: String? {
        CandidateInviteValidation.validityTimestampIssue(
            validFrom: trimmed(validFrom),
            validUntil: trimmed(validUntil)
        )
    }

    private var validityOrderIssue: String? {
        CandidateInviteValidation.validityOrderIssue(
            validFrom: trimmed(validFrom),
            validUntil: trimmed(validUntil)
        )
    }

    private var textValidationIssue: String? {
        CandidateInviteValidation.textIssue(.init(
            fullName: CandidateInviteValidation.normalizedFullName(fullName),
            tags: CandidateInviteValidation.normalizedTags(tags),
            evaluatorEmail: trimmed(evaluatorEmail),
            emailSubject: trimmed(emailSubject),
            emailMessage: trimmed(emailMessage),
            atsCandidateID: trimmed(atsCandidateID),
            atsRequisitionID: trimmed(atsRequisitionID)
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .disableAutocorrection(true)
                    TextField("Full name (optional)", text: $fullName)
                    Toggle("Send invitation email", isOn: $sendEmail)
                }

                Section {
                    TextField("Additional time (minutes)", text: $additionalTime)
                    TextField("Valid from (ISO-8601, optional)", text: $validFrom)
                    TextField("Valid until (ISO-8601, optional)", text: $validUntil)
                    TextField("Tags (comma-separated)", text: $tags)
                    TextField("Evaluator email", text: $evaluatorEmail)
                        .textContentType(.emailAddress)
                        .disableAutocorrection(true)
                    TextField("ATS candidate ID", text: $atsCandidateID)
                    TextField("ATS requisition ID", text: $atsRequisitionID)
                    if !templates.isEmpty {
                        Picker("Email template", selection: $selectedTemplateID) {
                            Text("None").tag(String?.none)
                            ForEach(templates.compactMap(\.id), id: \.self) { id in
                                Text(templateName(id)).tag(Optional(id))
                            }
                        }
                    }
                    TextField("Email subject", text: $emailSubject)
                    TextField("Email message", text: $emailMessage, axis: .vertical)
                        .lineLimit(2 ... 4)
                } header: {
                    Text("Invite options")
                } footer: {
                    if !additionalTimeValid {
                        Text("Additional time must be a whole number from 0 to 1,440 minutes.")
                            .foregroundStyle(.red)
                    } else if let validityTimestampIssue {
                        Text(validityTimestampIssue)
                            .foregroundStyle(.red)
                    } else if let validityOrderIssue {
                        Text(validityOrderIssue)
                            .foregroundStyle(.red)
                    } else if !evaluatorEmailValid {
                        Text("Evaluator email must look like an email address.")
                            .foregroundStyle(.red)
                    } else if let textValidationIssue {
                        Text(textValidationIssue)
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
            .navigationTitle("Invite Candidate")
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
                        Button("Invite") { mutationTask = Task { await invite() } }
                            .disabled(!canInvite)
                    }
                }
            }
        }
        .frame(width: 500, height: 560)
        .interactiveDismissDisabled(isSending)
        .task { await loadTemplates() }
        .onDisappear { mutationTask?.cancel() }
    }

    private func templateName(_ id: String) -> String {
        templates.first { $0.id == id }?.name ?? id
    }

    /// Loads the account's invitation email templates for the optional template picker,
    /// following the cursor (bounded to stay snappy). Best-effort: a failure just leaves
    /// the picker hidden, since a template has always been optional on an invite.
    private func loadTemplates() async {
        let client = HackerRankClient(account: account)
        var loaded: [InviteTemplate] = []
        var cursor: String?
        do {
            repeat {
                let page = try await client.inviteTemplatesPage(after: cursor)
                loaded.append(contentsOf: page.items)
                cursor = page.next
            } while cursor != nil && loaded.count < 200
        } catch {
            // Leave whatever loaded; the picker simply doesn't render when empty.
        }
        templates = loaded.filter { $0.id != nil }
    }

    private func trimmed(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private func invite() async {
        guard canInvite else { return }

        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await HackerRankClient(account: account).inviteCandidate(
                testID: testID,
                email: trimmedEmail,
                fullName: CandidateInviteValidation.normalizedFullName(fullName),
                sendEmail: sendEmail,
                options: CandidateInviteOptions(
                    validFrom: trimmed(validFrom),
                    validUntil: trimmed(validUntil),
                    emailSubject: trimmed(emailSubject),
                    emailMessage: trimmed(emailMessage),
                    templateID: selectedTemplateID,
                    evaluatorEmail: trimmed(evaluatorEmail),
                    tags: CandidateInviteValidation.normalizedTags(tags),
                    additionalTime: additionalTimeMinutes,
                    atsCandidateID: trimmed(atsCandidateID),
                    atsRequisitionID: trimmed(atsRequisitionID)
                )
            )
            onInvited()
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("Invite (demo)") {
    InviteCandidateSheet(testID: "t1", account: .demo) {}
}

#Preview("Invite (live)") {
    InviteCandidateSheet(
        testID: "t1",
        account: Account(label: "Work", token: "live-token"),
        onInvited: {}
    )
}
