//
//  RankBuddyToolProvider+Writes.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation
import HackerRankKit
import MCP
import MCPKit

extension RankBuddyToolProvider {
    static let writeToolNames: Set<String> = [
        "create_test", "update_test", "delete_test", "invite_candidate", "create_user",
        "create_team", "add_team_member", "remove_team_member", "create_pad", "schedule_interview"
    ]

    static func isWriteTool(_ name: String) -> Bool {
        writeToolNames.contains(name)
    }

    func callWriteTool(_ name: String, arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        if let result = await callTestWriteTool(name, arguments, account: account) { return result }
        if let result = await callTeamInterviewWriteTool(name, arguments, account: account) { return result }
        return errorResult("Unknown tool: \(name)")
    }

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

    private func callTeamInterviewWriteTool(
        _ name: String, _ arguments: [String: Value]?, account: String?
    ) async -> CallTool.Result? {
        switch name {
        case "create_team": await createTeamTool(arguments, account: account)
        case "add_team_member": await addTeamMemberTool(arguments, account: account)
        case "remove_team_member": await removeTeamMemberTool(arguments, account: account)
        case "create_pad": await createPadTool(arguments, account: account)
        case "schedule_interview": await scheduleInterviewTool(arguments, account: account)
        default: nil
        }
    }

    private func boolArgument(_ arguments: [String: Value]?, _ key: String) -> Bool? {
        if case let .bool(value)? = arguments?[key] { return value }
        return nil
    }

    private func intArgument(_ arguments: [String: Value]?, _ key: String) -> Int? {
        if case let .int(value)? = arguments?[key] { return value }
        return nil
    }

    private func stringArrayArgument(_ arguments: [String: Value]?, _ key: String) -> [String]? {
        if case let .array(values)? = arguments?[key] {
            let result = values.compactMap { value -> String? in
                guard case let .string(text) = value else { return nil }

                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return result.isEmpty ? nil : result
        }
        if let text = stringArgument(arguments, key) {
            let result = text.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return result.isEmpty ? nil : result
        }
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

        let additionalTime = intArgument(arguments, "additional_time")
        if let additionalTime, additionalTime < 0 {
            return errorResult("`additional_time` must be a non-negative whole number of minutes.")
        }

        do {
            let invited = try await HackerRankClient(account: resolved).inviteCandidate(
                testID: testID,
                email: email,
                fullName: stringArgument(arguments, "full_name"),
                sendEmail: boolArgument(arguments, "send_email") ?? true,
                options: CandidateInviteOptions(
                    validFrom: stringArgument(arguments, "valid_from"),
                    validUntil: stringArgument(arguments, "valid_until"),
                    emailSubject: stringArgument(arguments, "email_subject"),
                    emailMessage: stringArgument(arguments, "email_message"),
                    templateID: stringArgument(arguments, "template_id"),
                    evaluatorEmail: stringArgument(arguments, "evaluator_email"),
                    finishURL: stringArgument(arguments, "finish_url"),
                    resultURL: stringArgument(arguments, "result_url"),
                    notifyResultUpdate: boolArgument(arguments, "notify_result_update"),
                    tags: stringArrayArgument(arguments, "tags"),
                    force: boolArgument(arguments, "force"),
                    allowReattempt: boolArgument(arguments, "allow_reattempt"),
                    additionalTime: additionalTime,
                    atsCandidateID: stringArgument(arguments, "ats_candidate_id"),
                    atsRequisitionID: stringArgument(arguments, "ats_requisition_id")
                )
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
    private func createPadTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let created = try await HackerRankClient(account: resolved)
                .createPad(title: stringArgument(arguments, "title"))
            return jsonResult([
                "account": resolved.label,
                "created_interview": ["id": created.id ?? "", "url": created.url ?? ""]
            ])
        } catch {
            return errorResult("Couldn't create Pad: \(error.localizedDescription)")
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
    static var writeDescriptors: [[String: Any]] {
        let account: [String: Any] = [
            "type": "string", "description": "Account label or id; defaults to the current account."
        ]
        func string(_ description: String) -> [String: Any] {
            ["type": "string", "description": description]
        }
        func integer(_ description: String) -> [String: Any] {
            ["type": "integer", "description": description]
        }
        func boolean(_ description: String) -> [String: Any] {
            ["type": "boolean", "description": description]
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
                      "send_email": boolean("Email the invite (default true)."),
                      "additional_time": integer("Extra time accommodation in minutes."),
                      "valid_from": string("ISO-8601 timestamp before which the invite is inactive."),
                      "valid_until": string("ISO-8601 timestamp after which the invite expires."),
                      "email_subject": string("Custom invitation email subject."),
                      "email_message": string("Custom invitation email message."),
                      "template_id": string("Invitation email template id."),
                      "evaluator_email": string("Evaluator email assigned to the invite."),
                      "finish_url": string("URL to send the candidate to after finishing."),
                      "result_url": string("Result/report callback or redirect URL."),
                      "notify_result_update": boolean("Notify downstream systems when results update."),
                      "tags": ["type": "array", "items": ["type": "string"],
                               "description": "Candidate tags; a comma-separated string is also accepted."],
                      "force": boolean("Force creation when supported."),
                      "allow_reattempt": boolean("Allow the candidate to reattempt."),
                      "ats_candidate_id": string("External ATS candidate id."),
                      "ats_requisition_id": string("External ATS requisition/job id."),
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
            write("create_pad", "Create an instant collaborative Pad interview.",
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
