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
    static let descriptors: [[String: Any]] = {
        let account: [String: Any] = [
            "type": "string", "description": "Account label or id; defaults to the current account."
        ]
        let query: [String: Any] = ["type": "string", "description": "Case-insensitive substring to match."]
        func readOnly(
            _ name: String,
            _ description: String,
            properties: [String: Any],
            required: [String] = []
        ) -> [String: Any] {
            var schema: [String: Any] = ["type": "object", "properties": properties]
            if !required.isEmpty { schema["required"] = required }
            return [
                "name": name, "description": description,
                "annotations": ["readOnlyHint": true], "inputSchema": schema
            ]
        }
        return [
            readOnly("list_accounts", "List the configured RankBuddy accounts (no tokens).", properties: [:]),
            readOnly("list_tests", "List the current (or named) account's HackerRank tests (first page).",
                     properties: ["account": account]),
            readOnly("list_questions", "List the account's questions (first page).",
                     properties: ["account": account]),
            readOnly("list_interviews", "List the account's interviews (first page).",
                     properties: ["account": account]),
            readOnly("list_candidates", "List the candidates for a test.",
                     properties: ["test_id": ["type": "string", "description": "The test's id."], "account": account],
                     required: ["test_id"]),
            readOnly("search_tests", "Search the account's tests by name (bounded paging).",
                     properties: ["query": query, "account": account], required: ["query"]),
            readOnly("search_questions", "Search the account's questions by name (bounded paging).",
                     properties: ["query": query, "account": account], required: ["query"]),
            readOnly("search_interviews", "Search the account's interviews by title/status (bounded paging).",
                     properties: ["query": query, "account": account], required: ["query"])
        ]
    }()
}
