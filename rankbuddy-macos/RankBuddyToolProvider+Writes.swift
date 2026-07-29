//
//  RankBuddyToolProvider+Writes.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation
import HackerRankKit
import MCP
import MCPKit

// Write dispatch stays centralized so tool schemas and handlers remain aligned.
// swiftlint:disable file_length

extension RankBuddyToolProvider {
    static let writeToolNames: Set<String> = [
        "create_test", "update_test", "archive_test", "delete_test", "invite_candidate",
        "update_candidate", "cancel_candidate_invite", "delete_candidate_report",
        "create_user", "update_user", "lock_user",
        "create_team", "update_team", "delete_team", "add_team_member_by_user_id",
        "create_ats_codepair_invite", "create_ats_codescreen_invite",
        "add_team_member", "remove_team_member", "create_pad", "schedule_interview", "delete_interview",
        "create_question", "update_question", "delete_question", "delete_testcase", "delete_all_testcases"
    ]

    static func isWriteTool(_ name: String) -> Bool {
        writeToolNames.contains(name)
    }

    func callWriteTool(_ name: String, arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        if let result = await callTestWriteTool(name, arguments, account: account) { return result }
        if let result = await callTeamInterviewWriteTool(name, arguments, account: account) { return result }
        return errorResult("Unknown tool: \(name)")
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func callTestWriteTool(
        _ name: String, _ arguments: [String: Value]?, account: String?
    ) async -> CallTool.Result? {
        switch name {
        case "create_test": await createTestTool(arguments, account: account)
        case "update_test": await updateTestTool(arguments, account: account)
        case "archive_test": await archiveTestTool(arguments, account: account)
        case "delete_test": await deleteTestTool(arguments, account: account)
        case "invite_candidate": await inviteCandidateTool(arguments, account: account)
        case "update_candidate": await updateCandidateTool(arguments, account: account)
        case "cancel_candidate_invite": await cancelCandidateInviteTool(arguments, account: account)
        case "delete_candidate_report": await deleteCandidateReportTool(arguments, account: account)
        case "create_user": await createUserTool(arguments, account: account)
        case "update_user": await updateUserTool(arguments, account: account)
        case "lock_user": await lockUserTool(arguments, account: account)
        case "create_question": await createQuestionTool(arguments, account: account)
        case "update_question": await updateQuestionTool(arguments, account: account)
        case "delete_question": await deleteQuestionTool(arguments, account: account)
        case "delete_testcase": await deleteTestcaseTool(arguments, account: account)
        case "delete_all_testcases": await deleteAllTestcasesTool(arguments, account: account)
        default: nil
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func callTeamInterviewWriteTool(
        _ name: String, _ arguments: [String: Value]?, account: String?
    ) async -> CallTool.Result? {
        switch name {
        case "create_team": await createTeamTool(arguments, account: account)
        case "update_team": await updateTeamTool(arguments, account: account)
        case "delete_team": await deleteTeamTool(arguments, account: account)
        case "add_team_member": await addTeamMemberTool(arguments, account: account)
        case "add_team_member_by_user_id": await addTeamMemberByUserIDTool(arguments, account: account)
        case "remove_team_member": await removeTeamMemberTool(arguments, account: account)
        case "create_pad": await createPadTool(arguments, account: account)
        case "schedule_interview": await scheduleInterviewTool(arguments, account: account)
        case "delete_interview": await deleteInterviewTool(arguments, account: account)
        case "create_ats_codepair_invite": await createATSCodePairInviteTool(arguments, account: account)
        case "create_ats_codescreen_invite": await createATSCodeScreenInviteTool(arguments, account: account)
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
    private func archiveTestTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let testID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let archived = try await HackerRankClient(account: resolved).archiveTest(testID: testID)
            return jsonResult([
                "account": resolved.label,
                "archived_test": ["id": archived.id ?? testID, "name": archived.name ?? ""]
            ])
        } catch {
            return errorResult("Couldn't archive test: \(error.localizedDescription)")
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

    @MainActor
    private func updateCandidateTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let testID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
        guard let candidateID = stringArgument(arguments, "candidate_id") else {
            return missingArgument("candidate_id")
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let updated = try await HackerRankClient(account: resolved).updateCandidate(
                testID: testID,
                candidateID: candidateID,
                options: CandidateUpdateOptions(
                    fullName: stringArgument(arguments, "full_name"),
                    atsState: intArgument(arguments, "ats_state"),
                    inviteValidFrom: stringArgument(arguments, "invite_valid_from"),
                    inviteValidTo: stringArgument(arguments, "invite_valid_to"),
                    evaluatorEmail: stringArgument(arguments, "evaluator_email"),
                    testFinishURL: stringArgument(arguments, "test_finish_url"),
                    testResultURL: stringArgument(arguments, "test_result_url"),
                    acceptResultUpdates: boolArgument(arguments, "accept_result_updates"),
                    tags: stringArrayArgument(arguments, "tags")
                )
            )
            return jsonResult([
                "account": resolved.label,
                "updated_candidate": [
                    "id": updated.id,
                    "email": updated.email,
                    "name": updated.fullName ?? ""
                ]
            ])
        } catch {
            return errorResult("Couldn't update candidate: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func cancelCandidateInviteTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let testID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
        guard let candidateID = stringArgument(arguments, "candidate_id") else {
            return missingArgument("candidate_id")
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            _ = try await HackerRankClient(account: resolved).cancelCandidateInvite(
                testID: testID,
                candidateID: candidateID
            )
            return jsonResult([
                "account": resolved.label, "test_id": testID, "candidate_id": candidateID, "cancelled": true
            ])
        } catch {
            return errorResult("Couldn't cancel candidate invite: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func deleteCandidateReportTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let testID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
        guard let candidateID = stringArgument(arguments, "candidate_id") else {
            return missingArgument("candidate_id")
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            _ = try await HackerRankClient(account: resolved).deleteCandidateReport(
                testID: testID,
                candidateID: candidateID
            )
            return jsonResult([
                "account": resolved.label, "test_id": testID, "candidate_id": candidateID, "deleted_report": true
            ])
        } catch {
            return errorResult("Couldn't delete candidate report: \(error.localizedDescription)")
        }
    }

    // MARK: - Users

    @MainActor
    private func createUserTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let email = stringArgument(arguments, "email") else { return missingArgument("email") }

        // POST /users requires email, firstname, role, and a team (the server rejects the
        // request with HTTP 400 otherwise), so fail fast with a clear message instead of
        // relaying the 400. The last name is genuinely optional.
        guard let firstName = stringArgument(arguments, "first_name") else { return missingArgument("first_name") }
        guard let role = stringArgument(arguments, "role") else { return missingArgument("role") }
        guard let teamID = stringArgument(arguments, "team_id") else { return missingArgument("team_id") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let created = try await HackerRankClient(account: resolved).createUser(
                email: email,
                firstName: firstName,
                lastName: stringArgument(arguments, "last_name"),
                role: role,
                teamIDs: [teamID]
            )
            return jsonResult([
                "account": resolved.label,
                "created_user": ["id": created.id ?? "", "email": created.email ?? email]
            ])
        } catch {
            return errorResult("Couldn't create user: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func updateUserTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let userID = stringArgument(arguments, "user_id") else { return missingArgument("user_id") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let updated = try await HackerRankClient(account: resolved).updateUser(
                id: userID,
                options: UserUpdateOptions(
                    firstName: stringArgument(arguments, "first_name"),
                    lastName: stringArgument(arguments, "last_name"),
                    country: stringArgument(arguments, "country"),
                    role: stringArgument(arguments, "role"),
                    phone: stringArgument(arguments, "phone"),
                    questionsPermission: intArgument(arguments, "questions_permission"),
                    testsPermission: intArgument(arguments, "tests_permission"),
                    interviewsPermission: intArgument(arguments, "interviews_permission"),
                    candidatesPermission: intArgument(arguments, "candidates_permission"),
                    sharedQuestionsPermission: intArgument(arguments, "shared_questions_permission"),
                    sharedTestsPermission: intArgument(arguments, "shared_tests_permission"),
                    sharedInterviewsPermission: intArgument(arguments, "shared_interviews_permission"),
                    sharedCandidatesPermission: intArgument(arguments, "shared_candidates_permission"),
                    companyAdmin: boolArgument(arguments, "company_admin"),
                    teamAdmin: boolArgument(arguments, "team_admin")
                )
            )
            return jsonResult([
                "account": resolved.label,
                "updated_user": ["id": updated.id, "email": updated.email, "name": updated.displayName]
            ])
        } catch {
            return errorResult("Couldn't update user: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func lockUserTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let userID = stringArgument(arguments, "user_id") else { return missingArgument("user_id") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            _ = try await HackerRankClient(account: resolved).lockUser(id: userID)
            return jsonResult(["account": resolved.label, "locked_user_id": userID, "locked": true])
        } catch {
            return errorResult("Couldn't lock user: \(error.localizedDescription)")
        }
    }

    // MARK: - Questions

    @MainActor
    private func createQuestionTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let name = stringArgument(arguments, "name") else { return missingArgument("name") }
        guard let type = stringArgument(arguments, "type") else { return missingArgument("type") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let written = try await HackerRankClient(account: resolved).createQuestion(
                name: name,
                type: type,
                options: questionWriteOptions(arguments)
            )
            return jsonResult([
                "account": resolved.label,
                "created_question": ["id": written.id ?? "", "name": written.name ?? name, "type": written.type ?? type]
            ])
        } catch {
            return errorResult("Couldn't create question: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func updateQuestionTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let questionID = stringArgument(arguments, "question_id") else { return missingArgument("question_id") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let written = try await HackerRankClient(account: resolved).updateQuestion(
                questionID: questionID,
                name: stringArgument(arguments, "name"),
                type: stringArgument(arguments, "type"),
                options: questionWriteOptions(arguments)
            )
            return jsonResult([
                "account": resolved.label,
                "updated_question": [
                    "id": written.id ?? questionID,
                    "name": written.name ?? "",
                    "type": written.type ?? ""
                ]
            ])
        } catch {
            return errorResult("Couldn't update question: \(error.localizedDescription)")
        }
    }

    private func questionWriteOptions(_ arguments: [String: Value]?) -> QuestionWriteOptions {
        QuestionWriteOptions(
            status: stringArgument(arguments, "status"),
            languages: stringArrayArgument(arguments, "languages"),
            problemStatement: stringArgument(arguments, "problem_statement"),
            recommendedDuration: intArgument(arguments, "recommended_duration"),
            tags: stringArrayArgument(arguments, "tags"),
            maxScore: doubleArgument(arguments, "max_score"),
            skills: stringArrayArgument(arguments, "skills")
        )
    }

    private func doubleArgument(_ arguments: [String: Value]?, _ key: String) -> Double? {
        switch arguments?[key] {
        case let .double(value): value
        case let .int(value): Double(value)
        default: nil
        }
    }

    @MainActor
    private func deleteQuestionTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let questionID = stringArgument(arguments, "question_id") else { return missingArgument("question_id") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            _ = try await HackerRankClient(account: resolved).deleteQuestion(questionID: questionID)
            return jsonResult(["account": resolved.label, "deleted_question_id": questionID, "deleted": true])
        } catch {
            return errorResult("Couldn't delete question: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func deleteTestcaseTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let questionID = stringArgument(arguments, "question_id") else { return missingArgument("question_id") }
        guard let testcaseID = stringArgument(arguments, "testcase_id") else { return missingArgument("testcase_id") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            _ = try await HackerRankClient(account: resolved).deleteTestcase(
                questionID: questionID,
                testcaseID: testcaseID
            )
            return jsonResult([
                "account": resolved.label, "question_id": questionID, "deleted_testcase_id": testcaseID,
                "deleted": true
            ])
        } catch {
            return errorResult("Couldn't delete testcase: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func deleteAllTestcasesTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let questionID = stringArgument(arguments, "question_id") else { return missingArgument("question_id") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            _ = try await HackerRankClient(account: resolved).deleteAllTestcases(questionID: questionID)
            return jsonResult(["account": resolved.label, "question_id": questionID, "deleted_all_testcases": true])
        } catch {
            return errorResult("Couldn't delete testcases: \(error.localizedDescription)")
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
    private func updateTeamTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let teamID = stringArgument(arguments, "team_id") else { return missingArgument("team_id") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let updated = try await HackerRankClient(account: resolved).updateTeam(
                id: teamID,
                options: TeamUpdateOptions(
                    name: stringArgument(arguments, "name"),
                    recruiterCap: intArgument(arguments, "recruiter_cap"),
                    developerCap: intArgument(arguments, "developer_cap"),
                    inviteAs: stringArgument(arguments, "invite_as"),
                    locations: stringArrayArgument(arguments, "locations"),
                    departments: stringArrayArgument(arguments, "departments")
                )
            )
            return jsonResult([
                "account": resolved.label,
                "updated_team": ["id": updated.id, "name": updated.name]
            ])
        } catch {
            return errorResult("Couldn't update team: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func deleteTeamTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let teamID = stringArgument(arguments, "team_id") else { return missingArgument("team_id") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            _ = try await HackerRankClient(account: resolved).deleteTeam(id: teamID)
            return jsonResult(["account": resolved.label, "deleted_team_id": teamID, "deleted": true])
        } catch {
            return errorResult("Couldn't delete team: \(error.localizedDescription)")
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
    private func addTeamMemberByUserIDTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let teamID = stringArgument(arguments, "team_id") else { return missingArgument("team_id") }
        guard let userID = stringArgument(arguments, "user_id") else { return missingArgument("user_id") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let result = try await HackerRankClient(account: resolved).addTeamMember(
                teamID: teamID,
                userID: userID,
                license: stringArgument(arguments, "license")
            )
            return jsonResult([
                "account": resolved.label, "team_id": teamID,
                "added_member": ["id": result.id ?? userID, "email": result.email ?? ""]
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

    @MainActor
    private func deleteInterviewTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let interviewID = stringArgument(arguments, "interview_id") else {
            return missingArgument("interview_id")
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            _ = try await HackerRankClient(account: resolved).deleteInterview(id: interviewID)
            return jsonResult(["account": resolved.label, "deleted_interview_id": interviewID, "deleted": true])
        } catch {
            return errorResult("Couldn't delete interview: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func createATSCodePairInviteTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let title = stringArgument(arguments, "title") else { return missingArgument("title") }
        guard let requisitionID = stringArgument(arguments, "requisition_id") else {
            return missingArgument("requisition_id")
        }
        guard let candidateID = stringArgument(arguments, "candidate_id") else {
            return missingArgument("candidate_id")
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let result = try await HackerRankClient(account: resolved).createATSCodePairInvite(
                title: title,
                requisitionID: requisitionID,
                candidateID: candidateID,
                options: ATSCodePairOptions(sendEmail: boolArgument(arguments, "send_email"))
            )
            return jsonResult([
                "account": resolved.label,
                "ats_invite": [
                    "id": result.id ?? "",
                    "url": result.url ?? "",
                    "status": result.status ?? "",
                    "email": result.email ?? ""
                ]
            ])
        } catch {
            return errorResult("Couldn't create ATS CodePair invite: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func createATSCodeScreenInviteTool(
        _ arguments: [String: Value]?,
        account: String?
    ) async -> CallTool.Result {
        guard let testID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
        guard let requisitionID = stringArgument(arguments, "requisition_id") else {
            return missingArgument("requisition_id")
        }
        guard let candidateID = stringArgument(arguments, "candidate_id") else {
            return missingArgument("candidate_id")
        }
        guard let email = stringArgument(arguments, "email") else { return missingArgument("email") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let result = try await HackerRankClient(account: resolved).createATSCodeScreenInvite(
                testID: testID,
                requisitionID: requisitionID,
                candidateID: candidateID,
                email: email,
                options: ATSCodeScreenOptions(sendEmail: boolArgument(arguments, "send_email"))
            )
            return jsonResult([
                "account": resolved.label,
                "ats_invite": [
                    "id": result.id ?? "",
                    "url": result.url ?? "",
                    "status": result.status ?? "",
                    "email": result.email ?? email
                ]
            ])
        } catch {
            return errorResult("Couldn't create ATS CodeScreen invite: \(error.localizedDescription)")
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
            write("archive_test", "Archive a test.",
                  properties: ["test_id": string("The test's id."), "account": account],
                  required: ["test_id"]),
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
            write("update_candidate", "Update candidate metadata and invite settings.",
                  properties: [
                      "test_id": string("The test's id."),
                      "candidate_id": string("The candidate's id."),
                      "full_name": string("Candidate name."),
                      "ats_state": integer("ATS state code."),
                      "invite_valid_from": string("ISO-8601 timestamp before which the invite is inactive."),
                      "invite_valid_to": string("ISO-8601 timestamp after which the invite expires."),
                      "evaluator_email": string("Evaluator email assigned to the candidate."),
                      "test_finish_url": string("URL to send the candidate to after finishing."),
                      "test_result_url": string("Result/report callback or redirect URL."),
                      "accept_result_updates": boolean("Accept downstream result update notifications."),
                      "tags": ["type": "array", "items": ["type": "string"],
                               "description": "Candidate tags; a comma-separated string is also accepted."],
                      "account": account
                  ],
                  required: ["test_id", "candidate_id"]),
            write("cancel_candidate_invite", "Cancel an outstanding candidate invite.",
                  properties: ["test_id": string("The test's id."),
                               "candidate_id": string("The candidate's id."),
                               "account": account],
                  required: ["test_id", "candidate_id"], destructive: true),
            write("delete_candidate_report", "Delete a candidate report.",
                  properties: ["test_id": string("The test's id."),
                               "candidate_id": string("The candidate's id."),
                               "account": account],
                  required: ["test_id", "candidate_id"], destructive: true),
            write("create_user", "Create an organisation user.",
                  properties: [
                      "email": string("The user's email."), "first_name": string("The user's first name."),
                      "last_name": string("Last name (optional)."),
                      "role": string("Role: recruiter, developer, or interviewer."),
                      "team_id": string("Id of the team the user will belong to (see list_teams)."),
                      "account": account
                  ],
                  required: ["email", "first_name", "role", "team_id"]),
            write("update_user", "Update an organisation user.",
                  properties: [
                      "user_id": string("The user's id."),
                      "first_name": string("The user's first name."),
                      "last_name": string("The user's last name."),
                      "country": string("Country."),
                      "role": string("Role: recruiter, developer, or interviewer."),
                      "phone": string("Phone number."),
                      "questions_permission": integer("Questions permission level."),
                      "tests_permission": integer("Tests permission level."),
                      "interviews_permission": integer("Interviews permission level."),
                      "candidates_permission": integer("Candidates permission level."),
                      "shared_questions_permission": integer("Shared questions permission level."),
                      "shared_tests_permission": integer("Shared tests permission level."),
                      "shared_interviews_permission": integer("Shared interviews permission level."),
                      "shared_candidates_permission": integer("Shared candidates permission level."),
                      "company_admin": boolean("Whether the user is a company admin."),
                      "team_admin": boolean("Whether the user is a team admin."),
                      "account": account
                  ],
                  required: ["user_id"]),
            write("lock_user", "Lock an organisation user.",
                  properties: ["user_id": string("The user's id."), "account": account],
                  required: ["user_id"], destructive: true),
            write("create_question", "Create a question with shared metadata fields.",
                  properties: [
                      "name": string("The question's name."),
                      "type": string("Question type, such as coding or mcq."),
                      "status": string("Question lifecycle status."),
                      "languages": ["type": "array", "items": ["type": "string"],
                                    "description": "Allowed languages; a comma-separated string is also accepted."],
                      "problem_statement": string("Problem statement, typically Markdown or HTML."),
                      "recommended_duration": integer("Recommended duration in minutes."),
                      "tags": ["type": "array", "items": ["type": "string"],
                               "description": "Question tags; a comma-separated string is also accepted."],
                      "max_score": ["type": "number", "description": "Maximum achievable score."],
                      "skills": ["type": "array", "items": ["type": "string"],
                                 "description": "Skills assessed; a comma-separated string is also accepted."],
                      "account": account
                  ],
                  required: ["name", "type"]),
            write("update_question", "Update question metadata.",
                  properties: [
                      "question_id": string("The question's id."),
                      "name": string("The question's name."),
                      "type": string("Question type, such as coding or mcq."),
                      "status": string("Question lifecycle status."),
                      "languages": ["type": "array", "items": ["type": "string"],
                                    "description": "Allowed languages; a comma-separated string is also accepted."],
                      "problem_statement": string("Problem statement, typically Markdown or HTML."),
                      "recommended_duration": integer("Recommended duration in minutes."),
                      "tags": ["type": "array", "items": ["type": "string"],
                               "description": "Question tags; a comma-separated string is also accepted."],
                      "max_score": ["type": "number", "description": "Maximum achievable score."],
                      "skills": ["type": "array", "items": ["type": "string"],
                                 "description": "Skills assessed; a comma-separated string is also accepted."],
                      "account": account
                  ],
                  required: ["question_id"]),
            write("delete_question", "Delete a question.",
                  properties: ["question_id": string("The question's id."), "account": account],
                  required: ["question_id"], destructive: true),
            write("delete_testcase", "Delete a testcase from a question.",
                  properties: ["question_id": string("The question's id."),
                               "testcase_id": string("The testcase id."),
                               "account": account],
                  required: ["question_id", "testcase_id"], destructive: true),
            write("delete_all_testcases", "Delete all testcases from a question.",
                  properties: ["question_id": string("The question's id."), "account": account],
                  required: ["question_id"], destructive: true),
            write("create_team", "Create a team.",
                  properties: ["name": string("The team's name."), "account": account], required: ["name"]),
            write("update_team", "Update a team.",
                  properties: [
                      "team_id": string("The team's id."),
                      "name": string("The team's name."),
                      "recruiter_cap": integer("Recruiter seat cap."),
                      "developer_cap": integer("Developer seat cap."),
                      "invite_as": string("Default invite role."),
                      "locations": ["type": "array", "items": ["type": "string"],
                                    "description": "Team locations; a comma-separated string is also accepted."],
                      "departments": ["type": "array", "items": ["type": "string"],
                                      "description": "Team departments; a comma-separated string is also accepted."],
                      "account": account
                  ],
                  required: ["team_id"]),
            write("delete_team", "Delete a team.",
                  properties: ["team_id": string("The team's id."), "account": account],
                  required: ["team_id"], destructive: true),
            write("add_team_member", "Add a member to a team by email.",
                  properties: [
                      "team_id": string("The team's id."), "email": string("The member's email."),
                      "role": string("The member's role (optional)."), "account": account
                  ],
                  required: ["team_id", "email"]),
            write("add_team_member_by_user_id", "Add an existing user to a team by user id.",
                  properties: [
                      "team_id": string("The team's id."),
                      "user_id": string("The user's id."),
                      "license": string("Optional license value."),
                      "account": account
                  ],
                  required: ["team_id", "user_id"]),
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
                  required: ["title", "from"]),
            write("delete_interview", "Delete an interview.",
                  properties: ["interview_id": string("The interview's id."), "account": account],
                  required: ["interview_id"], destructive: true),
            write("create_ats_codepair_invite", "Create an ATS-backed interview invite.",
                  properties: [
                      "title": string("The invite title."),
                      "requisition_id": string("The ATS requisition id."),
                      "candidate_id": string("The ATS candidate id."),
                      "send_email": boolean("Email the invite."),
                      "account": account
                  ],
                  required: ["title", "requisition_id", "candidate_id"]),
            write("create_ats_codescreen_invite", "Create an ATS-backed test candidate invite.",
                  properties: [
                      "test_id": string("The test's id."),
                      "requisition_id": string("The ATS requisition id."),
                      "candidate_id": string("The ATS candidate id."),
                      "email": string("The candidate's email."),
                      "send_email": boolean("Email the invite."),
                      "account": account
                  ],
                  required: ["test_id", "requisition_id", "candidate_id", "email"])
        ]
    }
}
