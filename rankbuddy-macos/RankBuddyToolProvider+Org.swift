//
//  RankBuddyToolProvider+Org.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit
import MCP
import MCPKit

/// Org-enumeration read tools (#9): `list_users` and `list_teams`. Split out of
/// `RankBuddyToolProvider` so its file stays within the length budget. Like the other list
/// tools, each returns the first page and reports `has_more` so an assistant knows the org is
/// larger than the page shown.
extension RankBuddyToolProvider {
    nonisolated static func nullableCount(_ value: Int?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }

    /// Dispatches the org-enumeration tools.
    func callOrgListTool(
        _ name: String,
        arguments: [String: Value]?,
        account: String?
    ) async -> CallTool.Result {
        switch name {
        case "list_users":
            let cursor = Self.normalizedOptionalString(stringArgument(arguments, "cursor"))
            guard arguments?["cursor"] == nil || cursor != nil else {
                return errorResult("`cursor` must not be empty.")
            }

            return await listUsers(cursor: cursor, account: account)

        case "list_teams":
            let cursor = Self.normalizedOptionalString(stringArgument(arguments, "cursor"))
            guard arguments?["cursor"] == nil || cursor != nil else {
                return errorResult("`cursor` must not be empty.")
            }

            return await listTeams(cursor: cursor, account: account)

        default: return errorResult("Unknown tool: \(name)")
        }
    }

    @MainActor
    private func listUsers(cursor: String?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await HackerRankClient(account: resolved).usersPage(after: cursor)
            guard Self.allResourceIDsUsable(page.items.map(\.id)) else {
                return errorResult("HackerRank returned a user without a usable ID.")
            }
            let items = page.items.map {
                ["id": $0.id.trimmingCharacters(in: .whitespacesAndNewlines),
                 "email": $0.email, "name": $0.displayName, "role": $0.role ?? ""]
            }
            return jsonResult(pageMetadata(page).merging([
                "account": resolved.label, "users": items,
                "next_cursor": page.next ?? NSNull()
            ]) { _, value in value })
        } catch {
            return errorResult("Couldn't list users: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func listTeams(cursor: String?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await HackerRankClient(account: resolved).teamsPage(after: cursor)
            guard Self.allResourceIDsUsable(page.items.map(\.id)) else {
                return errorResult("HackerRank returned a team without a usable ID.")
            }
            let items = page.items.map { team in
                [
                    "id": team.id.trimmingCharacters(in: .whitespacesAndNewlines), "name": team.name,
                    "recruiters": Self.nullableCount(team.recruiterCount),
                    "developers": Self.nullableCount(team.developerCount),
                    "interviewers": Self.nullableCount(team.interviewerCount)
                ]
            }
            return jsonResult(pageMetadata(page).merging([
                "account": resolved.label, "teams": items,
                "next_cursor": page.next ?? NSNull()
            ]) { _, value in value })
        } catch {
            return errorResult("Couldn't list teams: \(error.localizedDescription)")
        }
    }
}
