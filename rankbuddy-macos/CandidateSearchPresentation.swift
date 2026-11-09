//
//  CandidateSearchPresentation.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit

/// Account-wide results describe a person and their attempts, rather than one test candidature.
struct CandidateSearchPresentation {
    let value: HackerRankJSONValue

    var name: String? {
        text("name") ?? text("full_name") ?? text("displayName")
    }

    var email: String? {
        text("email")
    }

    var identifier: String? {
        text("uuid") ?? text("id")
    }

    var title: String {
        name ?? email ?? "Unnamed candidate"
    }

    var subtitle: String? {
        name == nil ? (email == nil ? identifier : nil) : email
    }

    var attempts: [HackerRankJSONValue] {
        value.object["attempts"]?.array ?? []
    }

    var additionalFields: [String: HackerRankJSONValue] {
        value.object.filter { !["name", "full_name", "displayName", "email", "uuid", "id",
                                "created_at", "updated_at", "attempts"].contains($0.key) }
    }

    func text(_ field: String) -> String? {
        guard let value = value.object[field]?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }

        return value
    }

    func date(_ field: String) -> String? {
        DisplayFormat.date(text(field))
    }
}

struct CandidateAttemptPresentation {
    let value: HackerRankJSONValue
    let index: Int

    private var fields: CandidateSearchPresentation {
        CandidateSearchPresentation(value: value)
    }

    var title: String {
        fields.text("test_name") ?? fields.text("test_id").map { "Test \($0)" } ?? "Attempt \(index + 1)"
    }

    var namedTestID: String? {
        fields.text("test_name") == nil ? nil : fields.text("test_id")
    }

    var started: String? {
        fields.date("attempt_starttime")
    }

    var completed: String? {
        fields.date("attempt_endtime")
    }

    var reportURL: URL? {
        fields.text("report_url").flatMap(URL.remoteWebURL(from:))
    }

    func number(_ field: String) -> String? {
        guard let text = fields.text(field) else { return nil }

        return Double(text)?.formatted() ?? text
    }

    var additionalFields: [String: HackerRankJSONValue] {
        let presented = ["test_name", "test_id", "attempt_id", "score", "percentage_score",
                         "attempt_starttime", "attempt_endtime"] + (reportURL == nil ? [] : ["report_url"])
        return value.object.filter { !presented.contains($0.key) }
    }
}
