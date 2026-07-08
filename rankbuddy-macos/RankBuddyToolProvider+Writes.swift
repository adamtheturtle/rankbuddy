//
//  RankBuddyToolProvider+Writes.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation
import HackerRankKit
import MCP
import MCPKit

/// The MCP write tools (#73): create/update/delete over the HackerRank for Work data, mirroring
/// the app's own write flows (#12, #57–#60). Advertised and runnable only when the separate
/// "Allow the MCP server to make changes" opt-in is on; `RankBuddyToolProvider` gates both the
/// catalogue and dispatch on `allowWrites`. Every tool dispatches through the same
/// `HackerRankClient` the UI uses, so the demo account exercises them against the mock.
extension RankBuddyToolProvider {
    /// The names of the write tools, used to gate dispatch behind the opt-in.
    static let writeToolNames: Set<String> = [
        "create_test", "update_test", "delete_test", "invite_candidate", "create_user",
        "create_team", "add_team_member", "remove_team_member", "create_quickpad", "schedule_interview"
    ]

    /// Whether `name` is a write tool (so `callTool` can gate it on `allowWrites`).
    static func isWriteTool(_ name: String) -> Bool {
        writeToolNames.contains(name)
    }

    /// Dispatches a write tool. The caller (`callTool`) has already confirmed `allowWrites`. Split
    /// into two halves so neither dispatch switch trips the cyclomatic-complexity limit.
    func callWriteTool(_ name: String, arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        if let result = await callTestWriteTool(name, arguments, account: account) { return result }
        if let result = await callTeamInterviewWriteTool(name, arguments, account: account) { return result }
        return errorResult("Unknown tool: \(name)")
    }

    /// The tests/candidates/users write tools, or `nil` if `name` isn't one of them.
    private func callTestWriteTool(
        _ name: String, _ arguments: [String: Value]?, account: String?
    ) async -> CallTool.Result? {
        switch name {
        case "create_test": await createTestTool(arguments, account: account)
        case "update_test": await updateTestTool(arguments, account: account)
        case "delete_test": await deleteTestTool(arguments, account: account)
        case "invite_candidate": await inviteCandidateTool(arguments, account: account)
        case "create_user": await createUserTool(arguments, account: account)
        default: nil
        }
    }

    /// The teams/interviews write tools, or `nil` if `name` isn't one of them.
    private func callTeamInterviewWriteTool(
        _ name: String, _ arguments: [String: Value]?, account: String?
    ) async -> CallTool.Result? {
        switch name {
        case "create_team": await createTeamTool(arguments, account: account)
        case "add_team_member": await addTeamMemberTool(arguments, account: account)
        case "remove_team_member": await removeTeamMemberTool(arguments, account: account)
        case "create_quickpad": await createQuickPadTool(arguments, account: account)
        case "schedule_interview": await scheduleInterviewTool(arguments, account: account)
        default: nil
        }
    }

    /// A `Bool` argument, or `nil` when absent or not a boolean.
    private func boolArgument(_ arguments: [String: Value]?, _ key: String) -> Bool? {
        if case let .bool(value)? = arguments?[key] { return value }
        return nil
    }

    // MARK: - Tests

    @MainActor
    private func createTestTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let name = stringArgument(arguments, "name") else { return missingArgument("name") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let created = try await HackerRankClient(account: resolved).createTest(name: name)
            return jsonResult([
                "account": resolved.label,
                "created_test": ["id": created.id ?? "", "name": created.name ?? name]
            ])
        } catch {
            return errorResult("Couldn't create test: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func updateTestTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let testID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
        guard let name = stringArgument(arguments, "name") else { return missingArgument("name") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let updated = try await HackerRankClient(account: resolved).updateTest(testID: testID, name: name)
            return jsonResult([
                "account": resolved.label,
                "updated_test": ["id": updated.id ?? testID, "name": updated.name ?? name]
            ])
        } catch {
            return errorResult("Couldn't update test: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func deleteTestTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let testID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            _ = try await HackerRankClient(account: resolved).deleteTest(testID: testID)
            return jsonResult(["account": resolved.label, "deleted_test_id": testID, "deleted": true])
        } catch {
            return errorResult("Couldn't delete test: \(error.localizedDescription)")
        }
    }

    // MARK: - Candidates

    @MainActor
    private func inviteCandidateTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let testID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
        guard let email = stringArgument(arguments, "email") else { return missingArgument("email") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let invited = try await HackerRankClient(account: resolved).inviteCandidate(
                testID: testID,
                email: email,
                fullName: stringArgument(arguments, "full_name"),
                sendEmail: boolArgument(arguments, "send_email") ?? true
            )
            return jsonResult([
                "account": resolved.label, "test_id": testID,
                "invited_candidate": ["id": invited.id ?? "", "email": invited.email ?? email]
            ])
        } catch {
            return errorResult("Couldn't invite candidate: \(error.localizedDescription)")
        }
    }

    // MARK: - Users

    @MainActor
    private func createUserTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let email = stringArgument(arguments, "email") else { return missingArgument("email") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let created = try await HackerRankClient(account: resolved).createUser(
                email: email,
                firstName: stringArgument(arguments, "first_name"),
                lastName: stringArgument(arguments, "last_name"),
                role: stringArgument(arguments, "role")
            )
            return jsonResult([
                "account": resolved.label,
                "created_user": ["id": created.id ?? "", "email": created.email ?? email]
            ])
        } catch {
            return errorResult("Couldn't create user: \(error.localizedDescription)")
        }
    }

    // MARK: - Teams

    @MainActor
    private func createTeamTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let name = stringArgument(arguments, "name") else { return missingArgument("name") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let created = try await HackerRankClient(account: resolved).createTeam(name: name)
            return jsonResult([
                "account": resolved.label,
                "created_team": ["id": created.id ?? "", "name": created.name ?? name]
            ])
        } catch {
            return errorResult("Couldn't create team: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func addTeamMemberTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let teamID = stringArgument(arguments, "team_id") else { return missingArgument("team_id") }
        guard let email = stringArgument(arguments, "email") else { return missingArgument("email") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let result = try await HackerRankClient(account: resolved).addTeamMember(
                teamID: teamID, email: email, role: stringArgument(arguments, "role")
            )
            return jsonResult([
                "account": resolved.label, "team_id": teamID,
                "added_member": ["id": result.id ?? "", "email": result.email ?? email]
            ])
        } catch {
            return errorResult("Couldn't add team member: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func removeTeamMemberTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let teamID = stringArgument(arguments, "team_id") else { return missingArgument("team_id") }
        guard let userID = stringArgument(arguments, "user_id") else { return missingArgument("user_id") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            _ = try await HackerRankClient(account: resolved).removeTeamMember(teamID: teamID, userID: userID)
            return jsonResult([
                "account": resolved.label, "team_id": teamID, "removed_user_id": userID, "removed": true
            ])
        } catch {
            return errorResult("Couldn't remove team member: \(error.localizedDescription)")
        }
    }

    // MARK: - Interviews

    @MainActor
    private func createQuickPadTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let created = try await HackerRankClient(account: resolved)
                .createQuickPad(title: stringArgument(arguments, "title"))
            return jsonResult([
                "account": resolved.label,
                "created_interview": ["id": created.id ?? "", "url": created.url ?? ""]
            ])
        } catch {
            return errorResult("Couldn't create QuickPad: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func scheduleInterviewTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let title = stringArgument(arguments, "title") else { return missingArgument("title") }
        guard let fromText = stringArgument(arguments, "from") else { return missingArgument("from") }
        guard let from = ISO8601DateFormatter().date(from: fromText) else {
            return errorResult("`from` must be an ISO-8601 timestamp, e.g. 2026-07-01T14:00:00Z.")
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let created = try await HackerRankClient(account: resolved).scheduleInterview(
                title: title,
                from: from,
                candidateEmail: stringArgument(arguments, "candidate_email"),
                notes: stringArgument(arguments, "notes")
            )
            return jsonResult([
                "account": resolved.label,
                "scheduled_interview": ["id": created.id ?? "", "url": created.url ?? ""]
            ])
        } catch {
            return errorResult("Couldn't schedule interview: \(error.localizedDescription)")
        }
    }
}

// MARK: - Catalogue

extension RankBuddyToolProvider {
    /// The write tool descriptors, advertised only when `allowWrites` is on (#73). Each is flagged
    /// `readOnlyHint: false`; deletions/removals also carry `destructiveHint: true`.
    static var writeDescriptors: [[String: Any]] {
        let account: [String: Any] = [
            "type": "string", "description": "Account label or id; defaults to the current account."
        ]
        func string(_ description: String) -> [String: Any] {
            ["type": "string", "description": description]
        }
        func write(
            _ name: String,
            _ description: String,
            properties: [String: Any],
            required: [String],
            destructive: Bool = false
        ) -> [String: Any] {
            var annotations: [String: Any] = ["readOnlyHint": false]
            if destructive { annotations["destructiveHint"] = true }
            return [
                "name": name, "description": description, "annotations": annotations,
                "inputSchema": ["type": "object", "properties": properties, "required": required]
            ]
        }
        return [
            write("create_test", "Create a HackerRank test.",
                  properties: ["name": string("The test's name."), "account": account], required: ["name"]),
            write("update_test", "Rename a test.",
                  properties: ["test_id": string("The test's id."), "name": string("The new name."),
                               "account": account],
                  required: ["test_id", "name"]),
            write("delete_test", "Permanently delete a test.",
                  properties: ["test_id": string("The test's id."), "account": account],
                  required: ["test_id"], destructive: true),
            write("invite_candidate", "Invite a candidate to a test by email.",
                  properties: [
                      "test_id": string("The test's id."), "email": string("The candidate's email."),
                      "full_name": string("The candidate's name (optional)."),
                      "send_email": ["type": "boolean", "description": "Email the invite (default true)."],
                      "account": account
                  ],
                  required: ["test_id", "email"]),
            write("create_user", "Create an organisation user.",
                  properties: [
                      "email": string("The user's email."), "first_name": string("First name (optional)."),
                      "last_name": string("Last name (optional)."), "role": string("Role (optional)."),
                      "account": account
                  ],
                  required: ["email"]),
            write("create_team", "Create a team.",
                  properties: ["name": string("The team's name."), "account": account], required: ["name"]),
            write("add_team_member", "Add a member to a team by email.",
                  properties: [
                      "team_id": string("The team's id."), "email": string("The member's email."),
                      "role": string("The member's role (optional)."), "account": account
                  ],
                  required: ["team_id", "email"]),
            write("remove_team_member", "Remove a member from a team.",
                  properties: ["team_id": string("The team's id."), "user_id": string("The member's user id."),
                               "account": account],
                  required: ["team_id", "user_id"], destructive: true),
            write("create_quickpad", "Create an instant QuickPad interview.",
                  properties: ["title": string("The pad's title (optional)."), "account": account], required: []),
            write("schedule_interview", "Schedule an interview at an ISO-8601 start time.",
                  properties: [
                      "title": string("The interview's title."),
                      "from": string("Start time, ISO-8601 (e.g. 2026-07-01T14:00:00Z)."),
                      "candidate_email": string("The candidate's email (optional)."),
                      "notes": string("Notes (optional)."), "account": account
                  ],
                  required: ["title", "from"])
        ]
    }
}
