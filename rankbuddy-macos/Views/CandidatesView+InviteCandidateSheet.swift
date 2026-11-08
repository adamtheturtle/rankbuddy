//
//  CandidatesView+InviteCandidateSheet.swift
//  rankbuddy-macos
//

import Foundation
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
    nonisolated static let maxFullNameLength = 255
    nonisolated static let maxTagLength = 100
    nonisolated static let maxTagCount = 50
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

    static func fullNameIssue(_ value: String?) -> String? {
        guard let value, value.count > maxFullNameLength else { return nil }

        return "Full name can be at most \(maxFullNameLength) characters."
    }

    static func textIssue(_ fields: TextFields) -> String? {
        if let issue = fullNameIssue(fields.fullName) {
            return issue
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

nonisolated enum InviteTemplatePaging {
    struct NoProgress: Error {}

    static func next(_ cursor: String?, itemCount: Int, seen: inout Set<String>) throws -> String? {
        guard let cursor else { return nil }
        guard itemCount > 0, seen.insert(cursor).inserted else { throw NoProgress() }

        return cursor
    }

    static func appendUnique<Item, ID: Hashable>(
        _ incoming: [Item],
        to loaded: inout [Item],
        seenIDs: inout Set<ID>,
        id: (Item) -> ID?
    ) {
        for item in incoming {
            guard let itemID = id(item), seenIDs.insert(itemID).inserted else { continue }

            loaded.append(item)
        }
    }
}

/// A sheet that invites a candidate to a test (#12) — the app's first write flow. Refreshes
/// the list on success.
struct InviteCandidateSheet: View {
    let testID: String
    let account: Account
    var onInvited: () -> Void
    var body: some View {
        NativeFeatureFormSheet(title: "Invite Candidate", operationID: "api_invite_candidate", account: account,
                               path: ["test_id": testID], onSaved: onInvited)
    }
}
