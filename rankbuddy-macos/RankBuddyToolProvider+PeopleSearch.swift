//
//  RankBuddyToolProvider+PeopleSearch.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit
import MCP
import MCPKit

/// The server-side people/candidate search tools (#104), split out of `RankBuddyToolProvider`
/// so its file and `callKeyedTool` stay within the length/complexity budgets. Unlike the
/// `search_tests`/`search_questions`/`search_interviews` tools — which page through the list
/// client-side and match a substring — these hit the API's own `/users/search` and
/// `/tests/{id}/candidates/search` endpoints, so the org does the matching and a hit deep in a
/// large collection isn't gated on a bounded page scan.
extension RankBuddyToolProvider {
    /// Dispatches the two server-side search tools, validating their required arguments.
    func callPeopleSearchTool(
        _ name: String,
        arguments: [String: Value]?,
        account: String?
    ) async -> CallTool.Result {
        switch name {
        case "search_users":
            guard let rawQuery = stringArgument(arguments, "query") else { return missingArgument("query") }
            guard let query = Self.validatedSearchQuery(rawQuery) else {
                return errorResult("`query` must contain non-whitespace text.")
            }

            let cursor = Self.normalizedOptionalString(stringArgument(arguments, "cursor"))
            guard arguments?["cursor"] == nil || cursor != nil else {
                return errorResult("`cursor` must not be empty.")
            }

            return await searchUsers(query: query, cursor: cursor, account: account)

        case "search_candidates":
            guard let rawTestID = stringArgument(arguments, "test_id"),
                  let testID = Self.normalizedOptionalString(rawTestID) else {
                return errorResult("`test_id` is required and must not be empty.")
            }
            guard let rawQuery = stringArgument(arguments, "query") else { return missingArgument("query") }
            guard let query = Self.validatedSearchQuery(rawQuery) else {
                return errorResult("`query` must contain non-whitespace text.")
            }

            let cursor = Self.normalizedOptionalString(stringArgument(arguments, "cursor"))
            guard arguments?["cursor"] == nil || cursor != nil else {
                return errorResult("`cursor` must not be empty.")
            }

            return await searchCandidates(
                testID: testID,
                query: query,
                cursor: cursor,
                account: account
            )

        default:
            return errorResult("Unknown tool: \(name)")
        }
    }

    @MainActor
    private func searchUsers(query: String, cursor: String?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await HackerRankClient(account: resolved).searchUsers(query: query, after: cursor)
            let items = page.items.map {
                ["id": $0.id, "email": $0.email, "name": $0.displayName, "role": $0.role ?? ""]
            }
            return jsonResult([
                "account": resolved.label, "query": query, "matches": items,
                "count": items.count, "has_more": page.next != nil,
                "next_cursor": page.next ?? NSNull()
            ])
        } catch {
            return errorResult("Couldn't search users: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func searchCandidates(
        testID: String,
        query: String,
        cursor: String?,
        account: String?
    ) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await HackerRankClient(account: resolved)
                .searchCandidates(testID: testID, query: query, after: cursor)
            let items = page.items.map(Self.candidatePayload)
            return jsonResult([
                "account": resolved.label, "test_id": testID, "query": query, "matches": items,
                "count": items.count, "has_more": page.next != nil,
                "next_cursor": page.next ?? NSNull()
            ])
        } catch {
            return errorResult("Couldn't search candidates: \(error.localizedDescription)")
        }
    }
}
