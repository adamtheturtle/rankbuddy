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
    /// Dispatches the org-enumeration tools.
    func callOrgListTool(_ name: String, account: String?) async -> CallTool.Result {
        switch name {
        case "list_users": await listUsers(account: account)
        case "list_teams": await listTeams(account: account)
        default: errorResult("Unknown tool: \(name)")
        }
    }

    @MainActor
    private func listUsers(account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await HackerRankClient(account: resolved).usersPage()
            let items = page.items.map {
                ["id": $0.id, "email": $0.email, "name": $0.displayName, "role": $0.role ?? ""]
            }
            return jsonResult([
                "account": resolved.label, "users": items, "count": items.count, "has_more": page.next != nil
            ])
        } catch {
            return errorResult("Couldn't list users: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func listTeams(account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let page = try await HackerRankClient(account: resolved).teamsPage()
            let items = page.items.map { team in
                [
                    "id": team.id, "name": team.name,
                    "recruiters": team.recruiterCount ?? 0,
                    "developers": team.developerCount ?? 0,
                    "interviewers": team.interviewerCount ?? 0
                ]
            }
            return jsonResult([
                "account": resolved.label, "teams": items, "count": items.count, "has_more": page.next != nil
            ])
        } catch {
            return errorResult("Couldn't list teams: \(error.localizedDescription)")
        }
    }
}
