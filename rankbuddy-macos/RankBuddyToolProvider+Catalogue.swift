//
//  RankBuddyToolProvider+Catalogue.swift
//  rankbuddy-macos
//

import Foundation

/// The advertised read-tool descriptors (#9). Extracted from `RankBuddyToolProvider.swift` to
/// keep that file within the file-length budget; the write-tool descriptors live alongside the
/// write handlers in `RankBuddyToolProvider+Writes.swift`.
extension RankBuddyToolProvider {
    /// The advertised read tool descriptors. All read-only (`readOnlyHint`); list/search tools
    /// take an optional `account` (label or id), search tools also a required `query`.
    static var descriptors: [[String: Any]] {
        let account: [String: Any] = [
            "type": "string", "description": "Account label or id; defaults to the current account."
        ]
        let query: [String: Any] = [
            "type": "string", "minLength": 1,
            "description": "Non-empty, case-insensitive substring to match."
        ]
        let searchCursor: [String: Any] = [
            "type": "string", "minLength": 1,
            "description": "Opaque next_cursor from a preceding truncated search."
        ]
        func string(_ description: String) -> [String: Any] {
            ["type": "string", "description": description]
        }
        func readOnly(
            _ name: String,
            _ description: String,
            properties: [String: Any],
            required: [String] = []
        ) -> [String: Any] {
            var schema: [String: Any] = [
                "type": "object", "properties": properties, "additionalProperties": false
            ]
            if !required.isEmpty { schema["required"] = required }
            return [
                "name": name, "description": description,
                "annotations": ["readOnlyHint": true], "inputSchema": schema
            ]
        }
        return [
            readOnly("list_accounts", "List the configured RankBuddy accounts (no tokens).", properties: [:]),
            readOnly("list_tests", "List one page of the current (or named) account's HackerRank tests.",
                     properties: [
                         "cursor": string("Opaque next_cursor from the preceding page."),
                         "account": account
                     ]),
            readOnly("list_questions", "List one page of the account's questions.",
                     properties: [
                         "cursor": string("Opaque next_cursor from the preceding page."),
                         "account": account
                     ]),
            readOnly("list_interviews", "List one page of the account's interviews.",
                     properties: [
                         "cursor": string("Opaque next_cursor from the preceding page."),
                         "account": account
                     ]),
            readOnly("list_users", "List one page of the organisation's users/members.",
                     properties: [
                         "cursor": string("Opaque next_cursor from the preceding page."),
                         "account": account
                     ]),
            readOnly("list_teams", "List one page of the organisation's teams with member counts.",
                     properties: [
                         "cursor": string("Opaque next_cursor from the preceding page."),
                         "account": account
                     ]),
            readOnly("list_candidates", "List the candidates for a test.",
                     properties: [
                         "test_id": ["type": "string", "description": "The test's id."],
                         "cursor": string("Opaque next_cursor from the preceding page."),
                         "account": account
                     ],
                     required: ["test_id"]),
            readOnly("candidate_report_pdf", "Fetch a candidate report PDF URL.",
                     properties: [
                         "test_id": ["type": "string", "description": "The test's id."],
                         "candidate_id": ["type": "string", "description": "The candidate's id."],
                         "account": account
                     ],
                     required: ["test_id", "candidate_id"]),
            readOnly("list_invite_templates", "List invite email templates.",
                     properties: ["access": string("Optional access filter."), "account": account]),
            readOnly("get_invite_template", "Get an invite email template.",
                     properties: ["template_id": ["type": "string", "description": "The template id."],
                                  "account": account],
                     required: ["template_id"]),
            readOnly("list_interview_templates", "List interview templates.",
                     properties: ["account": account]),
            readOnly("get_interview_template", "Get an interview template.",
                     properties: ["template_id": ["type": "integer", "description": "The template id."],
                                  "account": account],
                     required: ["template_id"]),
            readOnly("search_tests", "Search the account's tests by name (bounded paging).",
                     properties: ["query": query, "cursor": searchCursor, "account": account], required: ["query"]),
            readOnly("search_questions", "Search the account's questions by name (bounded paging).",
                     properties: ["query": query, "cursor": searchCursor, "account": account], required: ["query"]),
            readOnly("search_interviews", "Search the account's interviews by title/status (bounded paging).",
                     properties: ["query": query, "cursor": searchCursor, "account": account], required: ["query"]),
            readOnly("search_users", "Search the organisation's users by name or email (server-side).",
                     properties: ["query": query, "cursor": searchCursor, "account": account], required: ["query"]),
            readOnly("search_candidates", "Search a test's candidates by name or email (server-side).",
                     properties: [
                         "test_id": ["type": "string", "description": "The test's id."],
                         "query": query, "cursor": searchCursor, "account": account
                     ],
                     required: ["test_id", "query"])
        ]
    }
}
