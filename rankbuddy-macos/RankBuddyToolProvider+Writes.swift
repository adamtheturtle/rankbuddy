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
    nonisolated static let supportedQuestionTypes = ["coding", "mcq", "subjective"]

    static let writeToolNames: Set<String> = [
        "create_test", "update_test", "archive_test", "delete_test", "invite_candidate",
        "update_candidate", "cancel_candidate_invite", "delete_candidate_report",
        "create_user", "update_user", "lock_user",
        "create_team", "update_team", "delete_team", "add_team_member_by_user_id",
        "create_ats_codepair_invite", "create_ats_codescreen_invite",
        "create_interview_template", "update_interview_template", "delete_interview_template",
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
        case "create_interview_template": await createInterviewTemplateTool(arguments, account: account)
        case "update_interview_template": await updateInterviewTemplateTool(arguments, account: account)
        case "delete_interview_template": await deleteInterviewTemplateTool(arguments, account: account)
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

    private func stringArrayArgument(
        _ arguments: [String: Value]?,
        _ key: String,
        preservingEmpty: Bool = false
    ) -> [String]? {
        if case let .array(values)? = arguments?[key] {
            let strings = values.compactMap { value -> String? in
                guard case let .string(text) = value else { return nil }

                return text
            }
            let result = Self.normalizedStringList(strings)
            return result.isEmpty && !preservingEmpty ? nil : result
        }

        if let text = stringArgument(arguments, key) {
            let result = Self.normalizedStringList(text.split(separator: ",").map(String.init))
            return result.isEmpty ? nil : result
        }
        return nil
    }

    private func hasInvalidStringArrayElements(_ arguments: [String: Value]?, _ key: String) -> Bool {
        guard case let .array(values)? = arguments?[key] else { return false }

        return values.contains { value in
            guard case let .string(text) = value else { return true }

            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: - Tests

    // swiftlint:disable function_body_length
    @MainActor
    private func createTestTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let rawName = stringArgument(arguments, "name") else { return missingArgument("name") }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return errorResult("`name` must not be empty.") }
        guard TestNameValidation.isValid(name) else {
            return errorResult("`name` can be at most \(TestNameValidation.maxLength) characters.")
        }

        if let error = testWriteValidationError(arguments) { return errorResult(error) }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let created = try await HackerRankClient(account: resolved).createTest(
                name: name,
                options: testWriteOptions(arguments)
            )
            guard let createdID = Self.validatedCreatedID(created.id) else {
                return errorResult("HackerRank created the test but returned no test ID.")
            }

            return jsonResult([
                "account": resolved.label,
                "created_test": ["id": createdID, "name": created.name ?? name]
            ])
        } catch {
            return errorResult("Couldn't create test: \(error.localizedDescription)")
        }
    }

    nonisolated static func validatedCreatedID(_ id: String?) -> String? {
        let normalized = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    nonisolated static func normalizedOptionalString(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    nonisolated static func normalizedStringList(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            guard let normalized = normalizedOptionalString(value) else { return nil }

            let key = normalized.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted ? normalized : nil
        }
    }

    nonisolated static func candidateWindowError(from: String?, until: String?) -> String? {
        let formatter = ISO8601DateFormatter()
        let fromDate = from.flatMap(formatter.date(from:))
        let toDate = until.flatMap(formatter.date(from:))
        if from != nil, fromDate == nil { return "`invite_valid_from` must be ISO-8601." }
        if until != nil, toDate == nil { return "`invite_valid_to` must be ISO-8601." }
        if let fromDate, let toDate, toDate <= fromDate {
            return "`invite_valid_to` must be later than `invite_valid_from`."
        }
        return nil
    }

    nonisolated static func hasCandidateUpdate(_ arguments: [String: Value]?) -> Bool {
        let textKeys = [
            "full_name", "invite_valid_from", "invite_valid_to", "evaluator_email",
            "test_finish_url", "test_result_url"
        ]
        if textKeys.contains(where: { key in
            guard case let .string(value)? = arguments?[key] else { return false }

            return normalizedOptionalString(value) != nil
        }) { return true }
        if case .int? = arguments?["ats_state"] { return true }
        if case .bool? = arguments?["accept_result_updates"] { return true }
        if case .array? = arguments?["tags"] { return true }
        if case let .string(value)? = arguments?["tags"] { return !normalizedStringList([value]).isEmpty }
        return false
    }

    nonisolated static func invalidUserPermissionKey(_ arguments: [String: Value]?) -> String? {
        let keys = [
            "questions_permission", "tests_permission", "interviews_permission", "candidates_permission",
            "shared_questions_permission", "shared_tests_permission",
            "shared_interviews_permission", "shared_candidates_permission"
        ]
        return keys.first { key in
            guard case let .int(value)? = arguments?[key] else { return false }

            return !(0 ... 3).contains(value)
        }
    }

    nonisolated static func hasUserUpdate(_ arguments: [String: Value]?) -> Bool {
        let requiredTextKeys = ["first_name", "role"]
        if requiredTextKeys.contains(where: { key in
            guard case let .string(value)? = arguments?[key] else { return false }

            return normalizedOptionalString(value) != nil
        }) { return true }
        let clearableTextKeys = ["last_name", "country", "phone"]
        if clearableTextKeys.contains(where: { if case .string? = arguments?[$0] { return true }; return false }) {
            return true
        }
        let integerKeys = [
            "questions_permission", "tests_permission", "interviews_permission", "candidates_permission",
            "shared_questions_permission", "shared_tests_permission",
            "shared_interviews_permission", "shared_candidates_permission"
        ]
        if integerKeys.contains(where: { if case .int? = arguments?[$0] { return true }; return false }) {
            return true
        }
        return ["company_admin", "team_admin"].contains {
            if case .bool? = arguments?[$0] { return true }
            return false
        }
    }

    nonisolated static func hasQuestionUpdate(_ arguments: [String: Value]?) -> Bool {
        let keys = [
            "name", "type", "status", "languages", "problem_statement",
            "recommended_duration", "tags", "max_score", "skills"
        ]
        return keys.contains { arguments?[$0] != nil }
    }

    private func testWriteValidationError(_ arguments: [String: Value]?) -> String? {
        if let duration = intArgument(arguments, "duration"), duration <= 0 {
            return "`duration` must be greater than zero."
        }
        if let cutoffScore = intArgument(arguments, "cutoff_score"), cutoffScore < 0 {
            return "`cutoff_score` must be zero or greater."
        }
        if hasInvalidStringArrayElements(arguments, "languages") {
            return "`languages` must contain only non-empty strings."
        }
        if hasInvalidStringArrayElements(arguments, "tags") {
            return "`tags` must contain only non-empty strings."
        }
        return TestScheduleValidation.error(
            startTime: stringArgument(arguments, "start_time") ?? "",
            endTime: stringArgument(arguments, "end_time") ?? ""
        )
    }

    private func testWriteOptions(_ arguments: [String: Value]?) -> TestWriteOptions {
        TestWriteOptions(
            duration: intArgument(arguments, "duration"),
            cutoffScore: intArgument(arguments, "cutoff_score"),
            instructions: stringArgument(arguments, "instructions"),
            startTime: stringArgument(arguments, "start_time"),
            endTime: stringArgument(arguments, "end_time"),
            languages: stringArrayArgument(arguments, "languages"),
            tags: stringArrayArgument(arguments, "tags"),
            shuffleQuestions: boolArgument(arguments, "shuffle_questions"),
            enableProctoring: boolArgument(arguments, "enable_proctoring")
        )
    }

    @MainActor
    private func updateTestTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let rawTestID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
        guard let rawName = stringArgument(arguments, "name") else { return missingArgument("name") }
        guard let testID = Self.normalizedOptionalString(rawTestID) else {
            return errorResult("`test_id` must not be empty.")
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TestNameValidation.isValid(name) else {
            return errorResult("`name` must contain 1 to \(TestNameValidation.maxLength) characters.")
        }

        if let error = testWriteValidationError(arguments) { return errorResult(error) }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let updated = try await HackerRankClient(account: resolved).updateTest(
                testID: testID,
                name: name,
                options: testWriteOptions(arguments)
            )
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
        guard let rawTestID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
        guard let testID = Self.normalizedOptionalString(rawTestID) else {
            return errorResult("`test_id` must not be empty.")
        }
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
        guard let rawTestID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }

        let testID = rawTestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !testID.isEmpty else { return errorResult("`test_id` must not be empty.") }
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
    // swiftlint:disable:next cyclomatic_complexity
    private func inviteCandidateTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let rawTestID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
        guard let rawEmail = stringArgument(arguments, "email") else { return missingArgument("email") }

        let testID = rawTestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let email = Self.normalizedOptionalString(rawEmail) else {
            return errorResult("`email` must not be empty.")
        }
        guard EmailValidation.isLikelyValid(email) else {
            return errorResult("`email` must be a valid email address.")
        }
        guard !testID.isEmpty else { return errorResult("`test_id` must not be empty.") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        let additionalTime = intArgument(arguments, "additional_time")
        guard CandidateInviteValidation.isValid(additionalTime: additionalTime) else {
            return errorResult("`additional_time` must be a whole number from 0 to 1,440 minutes.")
        }
        guard !hasInvalidStringArrayElements(arguments, "tags") else {
            return errorResult("Every `tags` array item must be a non-empty string.")
        }

        let fullName = stringArgument(arguments, "full_name")
        let tags = stringArrayArgument(arguments, "tags")
        let evaluatorEmail = Self.normalizedOptionalString(stringArgument(arguments, "evaluator_email"))
        guard evaluatorEmail.map(EmailValidation.isLikelyValid) ?? true else {
            return errorResult("`evaluator_email` must be a valid email address.")
        }

        let emailSubject = stringArgument(arguments, "email_subject")
        let emailMessage = stringArgument(arguments, "email_message")
        let atsCandidateID = stringArgument(arguments, "ats_candidate_id")
        let atsRequisitionID = stringArgument(arguments, "ats_requisition_id")
        let finishURL = Self.normalizedOptionalString(stringArgument(arguments, "finish_url"))
        let resultURL = Self.normalizedOptionalString(stringArgument(arguments, "result_url"))
        let validFrom = Self.normalizedOptionalString(stringArgument(arguments, "valid_from"))
        let validUntil = Self.normalizedOptionalString(stringArgument(arguments, "valid_until"))
        guard finishURL.map({ URL.remoteWebURL(from: $0) != nil }) ?? true else {
            return errorResult("`finish_url` must be a valid HTTP or HTTPS URL.")
        }
        guard resultURL.map({ URL.remoteWebURL(from: $0) != nil }) ?? true else {
            return errorResult("`result_url` must be a valid HTTP or HTTPS URL.")
        }

        if let issue = CandidateInviteValidation.validityTimestampIssue(
            validFrom: validFrom,
            validUntil: validUntil
        ) {
            return errorResult(issue)
        }

        if CandidateInviteValidation.validityOrderIssue(validFrom: validFrom, validUntil: validUntil) != nil {
            return errorResult("`valid_until` must be later than `valid_from`.")
        }

        if let issue = CandidateInviteValidation.textIssue(.init(
            fullName: fullName,
            tags: tags,
            evaluatorEmail: evaluatorEmail,
            emailSubject: emailSubject,
            emailMessage: emailMessage,
            atsCandidateID: atsCandidateID,
            atsRequisitionID: atsRequisitionID
        )) {
            return errorResult(issue)
        }

        do {
            let invited = try await HackerRankClient(account: resolved).inviteCandidate(
                testID: testID,
                email: email,
                fullName: fullName,
                sendEmail: boolArgument(arguments, "send_email") ?? true,
                options: CandidateInviteOptions(
                    validFrom: validFrom,
                    validUntil: validUntil,
                    emailSubject: emailSubject,
                    emailMessage: emailMessage,
                    templateID: stringArgument(arguments, "template_id"),
                    evaluatorEmail: evaluatorEmail,
                    finishURL: finishURL,
                    resultURL: resultURL,
                    notifyResultUpdate: boolArgument(arguments, "notify_result_update"),
                    tags: tags,
                    force: boolArgument(arguments, "force"),
                    allowReattempt: boolArgument(arguments, "allow_reattempt"),
                    additionalTime: additionalTime,
                    atsCandidateID: atsCandidateID,
                    atsRequisitionID: atsRequisitionID
                )
            )
            guard let invitedID = Self.validatedCreatedID(invited.id) else {
                return errorResult("HackerRank invited the candidate but returned no candidate ID.")
            }

            return jsonResult([
                "account": resolved.label, "test_id": testID,
                "invited_candidate": ["id": invitedID, "email": invited.email ?? email]
            ])
        } catch {
            return errorResult("Couldn't invite candidate: \(error.localizedDescription)")
        }
    }

    // swiftlint:enable function_body_length

    @MainActor
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func updateCandidateTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let rawTestID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
        guard let rawCandidateID = stringArgument(arguments, "candidate_id") else {
            return missingArgument("candidate_id")
        }
        guard let testID = Self.normalizedOptionalString(rawTestID) else {
            return errorResult("`test_id` must not be empty.")
        }
        guard let candidateID = Self.normalizedOptionalString(rawCandidateID) else {
            return errorResult("`candidate_id` must not be empty.")
        }
        guard Self.hasCandidateUpdate(arguments) else {
            return errorResult("At least one candidate field must be provided.")
        }

        let rawFinishURL = Self.normalizedOptionalString(stringArgument(arguments, "test_finish_url"))
        let rawResultURL = Self.normalizedOptionalString(stringArgument(arguments, "test_result_url"))
        let finishURL = rawFinishURL.flatMap { URL.remoteWebURL(from: $0)?.absoluteString }
        let resultURL = rawResultURL.flatMap { URL.remoteWebURL(from: $0)?.absoluteString }
        let evaluatorEmail = Self.normalizedOptionalString(stringArgument(arguments, "evaluator_email"))
        let validFrom = Self.normalizedOptionalString(stringArgument(arguments, "invite_valid_from"))
        let validTo = Self.normalizedOptionalString(stringArgument(arguments, "invite_valid_to"))
        let atsState = intArgument(arguments, "ats_state")
        if let error = Self.candidateWindowError(from: validFrom, until: validTo) { return errorResult(error) }
        if hasInvalidStringArrayElements(arguments, "tags") {
            return errorResult("`tags` must contain only non-empty strings.")
        }
        guard atsState.map({ CandidateATSState(rawValue: $0) != nil }) ?? true else {
            return errorResult("`ats_state` must be a documented HackerRank ATS state from 0 to 22.")
        }
        guard rawFinishURL == nil || finishURL != nil else {
            return errorResult("`test_finish_url` must be a valid HTTP or HTTPS URL.")
        }
        guard rawResultURL == nil || resultURL != nil else {
            return errorResult("`test_result_url` must be a valid HTTP or HTTPS URL.")
        }
        guard evaluatorEmail.map(EmailValidation.isLikelyValid) ?? true else {
            return errorResult("`evaluator_email` must be a valid email address.")
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let updated = try await HackerRankClient(account: resolved).updateCandidate(
                testID: testID,
                candidateID: candidateID,
                options: CandidateUpdateOptions(
                    fullName: stringArgument(arguments, "full_name"),
                    atsState: atsState,
                    inviteValidFrom: validFrom,
                    inviteValidTo: validTo,
                    evaluatorEmail: evaluatorEmail,
                    testFinishURL: finishURL,
                    testResultURL: resultURL,
                    acceptResultUpdates: boolArgument(arguments, "accept_result_updates"),
                    tags: stringArrayArgument(arguments, "tags", preservingEmpty: true)
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
        guard let rawTestID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
        guard let rawCandidateID = stringArgument(arguments, "candidate_id") else {
            return missingArgument("candidate_id")
        }
        guard let testID = Self.normalizedOptionalString(rawTestID) else {
            return errorResult("`test_id` must not be empty.")
        }
        guard let candidateID = Self.normalizedOptionalString(rawCandidateID) else {
            return errorResult("`candidate_id` must not be empty.")
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
        guard let rawTestID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
        guard let rawCandidateID = stringArgument(arguments, "candidate_id") else {
            return missingArgument("candidate_id")
        }
        guard let testID = Self.normalizedOptionalString(rawTestID) else {
            return errorResult("`test_id` must not be empty.")
        }
        guard let candidateID = Self.normalizedOptionalString(rawCandidateID) else {
            return errorResult("`candidate_id` must not be empty.")
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
    // swiftlint:disable:next cyclomatic_complexity
    private func createUserTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let rawEmail = stringArgument(arguments, "email") else { return missingArgument("email") }

        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailValidation.isLikelyValid(email) else {
            return errorResult("`email` must be a valid email address.")
        }

        // POST /users requires email, firstname, role, and a team (the server rejects the
        // request with HTTP 400 otherwise), so fail fast with a clear message instead of
        // relaying the 400. The last name is genuinely optional.
        guard let rawFirstName = stringArgument(arguments, "first_name") else {
            return missingArgument("first_name")
        }
        guard let rawRole = stringArgument(arguments, "role") else { return missingArgument("role") }

        let firstName = rawFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastName = Self.normalizedOptionalString(stringArgument(arguments, "last_name"))
        let role = rawRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !firstName.isEmpty else { return errorResult("`first_name` must not be empty.") }

        if let issue = UserNameValidation.issue(firstName: firstName, lastName: lastName) {
            return errorResult(issue)
        }
        guard ["recruiter", "developer", "interviewer"].contains(role) else {
            return errorResult("`role` must be recruiter, developer, or interviewer.")
        }
        guard let rawTeamID = stringArgument(arguments, "team_id") else { return missingArgument("team_id") }

        let teamID = rawTeamID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !teamID.isEmpty else { return errorResult("`team_id` must not be empty.") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let created = try await HackerRankClient(account: resolved).createUser(
                email: email,
                firstName: firstName,
                lastName: lastName,
                role: role,
                teamIDs: [teamID]
            )
            guard let userID = Self.validatedCreatedID(created.id) else {
                return errorResult("HackerRank created the user but returned no user ID.")
            }

            return jsonResult([
                "account": resolved.label,
                "created_user": ["id": userID, "email": created.email ?? email]
            ])
        } catch {
            return errorResult("Couldn't create user: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func updateUserTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let rawUserID = stringArgument(arguments, "user_id") else { return missingArgument("user_id") }
        guard let userID = Self.normalizedOptionalString(rawUserID) else {
            return errorResult("`user_id` must not be empty.")
        }
        guard Self.hasUserUpdate(arguments) else {
            return errorResult("At least one user field must be provided.")
        }

        let rawRole = stringArgument(arguments, "role")
        let role = Self.normalizedOptionalString(rawRole)?.lowercased()
        let allowedRoles = ["recruiter", "developer", "interviewer"]
        guard rawRole == nil || role.map(allowedRoles.contains) == true else {
            return errorResult("`role` must be recruiter, developer, or interviewer.")
        }

        if let invalidKey = Self.invalidUserPermissionKey(arguments) {
            return errorResult("`\(invalidKey)` must be a permission level from 0 to 3.")
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let updated = try await HackerRankClient(account: resolved).updateUser(
                id: userID,
                options: UserUpdateOptions(
                    firstName: stringArgument(arguments, "first_name"),
                    lastName: stringArgument(arguments, "last_name"),
                    country: stringArgument(arguments, "country"),
                    role: role,
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
        guard let rawUserID = stringArgument(arguments, "user_id") else { return missingArgument("user_id") }
        guard let userID = Self.normalizedOptionalString(rawUserID) else {
            return errorResult("`user_id` must not be empty.")
        }
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
    // swiftlint:disable:next cyclomatic_complexity
    private func createQuestionTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let rawName = stringArgument(arguments, "name") else { return missingArgument("name") }
        guard let rawType = stringArgument(arguments, "type") else { return missingArgument("type") }
        guard let name = Self.normalizedOptionalString(rawName) else {
            return errorResult("`name` must not be empty.")
        }
        guard let type = Self.normalizedOptionalString(rawType)?.lowercased(),
              Self.supportedQuestionTypes.contains(type)
        else {
            return errorResult("`type` must be coding, mcq, or subjective.")
        }
        let status = Self.normalizedOptionalString(stringArgument(arguments, "status"))?.lowercased()
        guard arguments?["status"] == nil || status.flatMap(QuestionLifecycleStatus.init(rawValue:)) != nil else {
            return errorResult("`status` must be active or archived.")
        }
        guard doubleArgument(arguments, "max_score").map({ $0.isFinite && $0 >= 0 }) ?? true else {
            return errorResult("`max_score` must be a finite number of zero or greater.")
        }
        guard intArgument(arguments, "recommended_duration").map({ $0 >= 0 }) ?? true else {
            return errorResult("`recommended_duration` must be zero or greater.")
        }
        if let error = questionListValidationError(arguments) { return errorResult(error) }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let written = try await HackerRankClient(account: resolved).createQuestion(
                name: name,
                type: type,
                options: questionWriteOptions(arguments, status: status)
            )
            guard let questionID = Self.validatedCreatedID(written.id) else {
                return errorResult("HackerRank created the question but returned no question ID.")
            }

            return jsonResult([
                "account": resolved.label,
                "created_question": ["id": questionID, "name": written.name ?? name, "type": written.type ?? type]
            ])
        } catch {
            return errorResult("Couldn't create question: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func updateQuestionTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let rawQuestionID = stringArgument(arguments, "question_id") else {
            return missingArgument("question_id")
        }
        guard let questionID = Self.normalizedOptionalString(rawQuestionID) else {
            return errorResult("`question_id` must not be empty.")
        }
        guard Self.hasQuestionUpdate(arguments) else {
            return errorResult("At least one question field must be provided.")
        }

        let rawName = stringArgument(arguments, "name")
        let name = Self.normalizedOptionalString(rawName)
        let rawType = stringArgument(arguments, "type")
        let type = Self.normalizedOptionalString(rawType)?.lowercased()
        guard rawType == nil || type.map(Self.supportedQuestionTypes.contains) == true else {
            return errorResult("`type` must be coding, mcq, or subjective.")
        }
        let status = Self.normalizedOptionalString(stringArgument(arguments, "status"))?.lowercased()
        guard arguments?["status"] == nil || status.flatMap(QuestionLifecycleStatus.init(rawValue:)) != nil else {
            return errorResult("`status` must be active or archived.")
        }
        guard doubleArgument(arguments, "max_score").map({ $0.isFinite && $0 >= 0 }) ?? true else {
            return errorResult("`max_score` must be a finite number of zero or greater.")
        }
        guard intArgument(arguments, "recommended_duration").map({ $0 >= 0 }) ?? true else {
            return errorResult("`recommended_duration` must be zero or greater.")
        }
        if let error = questionUpdateValidationError(arguments, name: name) { return errorResult(error) }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let written = try await HackerRankClient(account: resolved).updateQuestion(
                questionID: questionID,
                name: name,
                type: type,
                options: questionWriteOptions(arguments, status: status)
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

    private func questionWriteOptions(_ arguments: [String: Value]?, status: String?) -> QuestionWriteOptions {
        QuestionWriteOptions(
            status: status,
            languages: stringArrayArgument(arguments, "languages"),
            problemStatement: stringArgument(arguments, "problem_statement"),
            recommendedDuration: intArgument(arguments, "recommended_duration"),
            tags: stringArrayArgument(arguments, "tags"),
            maxScore: doubleArgument(arguments, "max_score"),
            skills: stringArrayArgument(arguments, "skills")
        )
    }

    private func questionListValidationError(_ arguments: [String: Value]?) -> String? {
        for key in ["languages", "tags", "skills"] where hasInvalidStringArrayElements(arguments, key) {
            return "`\(key)` must contain only non-empty strings."
        }
        return nil
    }

    private func questionUpdateValidationError(
        _ arguments: [String: Value]?,
        name: String?
    ) -> String? {
        if arguments?["name"] != nil, name == nil { return "`name` must not be empty." }
        return questionListValidationError(arguments)
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
        guard let rawQuestionID = stringArgument(arguments, "question_id") else {
            return missingArgument("question_id")
        }
        guard let questionID = Self.normalizedOptionalString(rawQuestionID) else {
            return errorResult("`question_id` must not be empty.")
        }
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
        guard let rawQuestionID = stringArgument(arguments, "question_id") else {
            return missingArgument("question_id")
        }
        guard let rawTestcaseID = stringArgument(arguments, "testcase_id") else {
            return missingArgument("testcase_id")
        }
        guard let questionID = Self.normalizedOptionalString(rawQuestionID) else {
            return errorResult("`question_id` must not be empty.")
        }
        guard let testcaseID = Self.normalizedOptionalString(rawTestcaseID) else {
            return errorResult("`testcase_id` must not be empty.")
        }
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
        guard let rawQuestionID = stringArgument(arguments, "question_id") else {
            return missingArgument("question_id")
        }
        guard let questionID = Self.normalizedOptionalString(rawQuestionID) else {
            return errorResult("`question_id` must not be empty.")
        }
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
        guard let rawName = stringArgument(arguments, "name") else { return missingArgument("name") }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return errorResult("`name` must not be empty.") }
        guard TeamNameValidation.isValid(name) else {
            return errorResult("`name` can be at most \(TeamNameValidation.maxLength) characters.")
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let created = try await HackerRankClient(account: resolved).createTeam(name: name)
            guard let teamID = Self.validatedCreatedID(created.id) else {
                return errorResult("HackerRank created the team but returned no team ID.")
            }

            return jsonResult([
                "account": resolved.label,
                "created_team": ["id": teamID, "name": created.name ?? name]
            ])
        } catch {
            return errorResult("Couldn't create team: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func updateTeamTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let rawTeamID = stringArgument(arguments, "team_id") else { return missingArgument("team_id") }
        guard let teamID = Self.normalizedOptionalString(rawTeamID) else {
            return errorResult("`team_id` must not be empty.")
        }

        let allowedInviteRoles = ["recruiter", "interviewer", "developer"]
        let inviteAs = Self.normalizedOptionalString(stringArgument(arguments, "invite_as"))?.lowercased()
        let rawName = stringArgument(arguments, "name")
        let name = Self.normalizedOptionalString(rawName)
        let recruiterCap = intArgument(arguments, "recruiter_cap")
        let developerCap = intArgument(arguments, "developer_cap")
        let locations = stringArrayArgument(arguments, "locations", preservingEmpty: true)
        let departments = stringArrayArgument(arguments, "departments", preservingEmpty: true)
        for key in ["locations", "departments"] where hasInvalidStringArrayElements(arguments, key) {
            return errorResult("`\(key)` must contain only non-empty strings.")
        }
        guard rawName == nil || name != nil else { return errorResult("`name` must not be empty.") }
        guard inviteAs.map(allowedInviteRoles.contains) ?? true else {
            return errorResult("`invite_as` must be recruiter, interviewer, or developer.")
        }
        guard recruiterCap.map({ $0 >= 0 }) ?? true else {
            return errorResult("`recruiter_cap` must be zero or greater.")
        }
        guard developerCap.map({ $0 >= 0 }) ?? true else {
            return errorResult("`developer_cap` must be zero or greater.")
        }
        guard name != nil || recruiterCap != nil || developerCap != nil || inviteAs != nil ||
            locations != nil || departments != nil
        else {
            return errorResult("At least one team field must be provided.")
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let updated = try await HackerRankClient(account: resolved).updateTeam(
                id: teamID,
                options: TeamUpdateOptions(
                    name: name,
                    recruiterCap: recruiterCap,
                    developerCap: developerCap,
                    inviteAs: inviteAs,
                    locations: locations,
                    departments: departments
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
        guard let rawTeamID = stringArgument(arguments, "team_id") else { return missingArgument("team_id") }
        guard let teamID = Self.normalizedOptionalString(rawTeamID) else {
            return errorResult("`team_id` must not be empty.")
        }
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
        guard let rawTeamID = stringArgument(arguments, "team_id") else { return missingArgument("team_id") }
        guard let rawEmail = stringArgument(arguments, "email") else { return missingArgument("email") }
        guard let teamID = Self.normalizedOptionalString(rawTeamID) else {
            return errorResult("`team_id` must not be empty.")
        }

        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailValidation.isLikelyValid(email) else {
            return errorResult("`email` must be a valid email address.")
        }

        let allowedRoles = ["recruiter", "interviewer", "developer"]
        let role = stringArgument(arguments, "role")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard role.map(allowedRoles.contains) ?? true else {
            return errorResult("`role` must be recruiter, interviewer, or developer.")
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let result = try await HackerRankClient(account: resolved).addTeamMember(
                teamID: teamID, email: email, role: role
            )
            guard let memberID = Self.validatedCreatedID(result.id) else {
                return errorResult("HackerRank added the team member but returned no user ID.")
            }

            return jsonResult([
                "account": resolved.label, "team_id": teamID,
                "added_member": ["id": memberID, "email": result.email ?? email]
            ])
        } catch {
            return errorResult("Couldn't add team member: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func addTeamMemberByUserIDTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let rawTeamID = stringArgument(arguments, "team_id") else { return missingArgument("team_id") }
        guard let rawUserID = stringArgument(arguments, "user_id") else { return missingArgument("user_id") }
        guard let teamID = Self.normalizedOptionalString(rawTeamID) else {
            return errorResult("`team_id` must not be empty.")
        }
        guard let userID = Self.normalizedOptionalString(rawUserID) else {
            return errorResult("`user_id` must not be empty.")
        }
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
        guard let rawTeamID = stringArgument(arguments, "team_id") else { return missingArgument("team_id") }
        guard let rawUserID = stringArgument(arguments, "user_id") else { return missingArgument("user_id") }

        let teamID = rawTeamID.trimmingCharacters(in: .whitespacesAndNewlines)
        let userID = rawUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !teamID.isEmpty else { return errorResult("`team_id` must not be empty.") }
        guard !userID.isEmpty else { return errorResult("`user_id` must not be empty.") }
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
                .createPad(title: PadTitleValidation.normalized(stringArgument(arguments, "title")))
            let createdID = Self.validatedCreatedID(created.id)
            let createdURL = created.url.flatMap(URL.remoteWebURL(from:))?.absoluteString
            guard createdID != nil || createdURL != nil else {
                return errorResult("HackerRank created the Pad but returned no usable ID or URL.")
            }

            return jsonResult([
                "account": resolved.label,
                "created_interview": ["id": createdID ?? "", "url": createdURL ?? ""]
            ])
        } catch {
            return errorResult("Couldn't create Pad: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func scheduleInterviewTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let rawTitle = stringArgument(arguments, "title") else { return missingArgument("title") }
        guard let fromText = stringArgument(arguments, "from") else { return missingArgument("from") }
        guard let title = Self.normalizedOptionalString(rawTitle) else {
            return errorResult("`title` must not be empty.")
        }
        guard let from = DisplayFormat.parseDate(fromText) else {
            return errorResult("`from` must be an ISO-8601 timestamp, e.g. 2026-07-01T14:00:00Z.")
        }
        guard from > Date() else {
            return errorResult("`from` must be a future timestamp.")
        }

        let candidateEmail = stringArgument(arguments, "candidate_email")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = stringArgument(arguments, "notes")
        guard candidateEmail.map({ $0.isEmpty || EmailValidation.isLikelyValid($0) }) ?? true else {
            return errorResult("`candidate_email` must be a valid email address.")
        }

        if let issue = InterviewScheduleValidation.textIssue(
            title: title,
            candidateEmail: candidateEmail,
            notes: notes
        ) {
            return errorResult(issue)
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let created = try await HackerRankClient(account: resolved).scheduleInterview(
                title: title,
                from: from,
                candidateEmail: candidateEmail.flatMap { $0.isEmpty ? nil : $0 },
                notes: notes
            )
            let createdID = Self.validatedCreatedID(created.id)
            let createdURL = created.url.flatMap(URL.remoteWebURL(from:))?.absoluteString
            guard createdID != nil || createdURL != nil else {
                return errorResult("HackerRank scheduled the interview but returned no usable ID or URL.")
            }

            return jsonResult([
                "account": resolved.label,
                "scheduled_interview": ["id": createdID ?? "", "url": createdURL ?? ""]
            ])
        } catch {
            return errorResult("Couldn't schedule interview: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func deleteInterviewTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let rawInterviewID = stringArgument(arguments, "interview_id") else {
            return missingArgument("interview_id")
        }
        guard let interviewID = Self.normalizedOptionalString(rawInterviewID) else {
            return errorResult("`interview_id` must not be empty.")
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
    private func createInterviewTemplateTool(
        _ arguments: [String: Value]?,
        account: String?
    ) async -> CallTool.Result {
        guard let rawName = stringArgument(arguments, "name") else { return missingArgument("name") }
        guard let name = Self.normalizedOptionalString(rawName) else {
            return errorResult("`name` must not be empty.")
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let template = try await HackerRankClient(account: resolved).createInterviewTemplate(
                options: InterviewTemplateWriteOptions(
                    name: name,
                    title: Self.normalizedOptionalString(stringArgument(arguments, "title")),
                    description: Self.normalizedOptionalString(stringArgument(arguments, "description"))
                )
            )
            return interviewTemplateResult(template, account: resolved.label)
        } catch {
            return errorResult("Couldn't create interview template: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func updateInterviewTemplateTool(
        _ arguments: [String: Value]?,
        account: String?
    ) async -> CallTool.Result {
        guard let templateID = intArgument(arguments, "template_id") else {
            return missingArgument("template_id")
        }
        guard templateID > 0 else { return errorResult("`template_id` must be greater than zero.") }

        let name = Self.normalizedOptionalString(stringArgument(arguments, "name"))
        if arguments?["name"] != nil, name == nil {
            return errorResult("`name` must not be empty.")
        }
        let title = stringArgument(arguments, "title")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let description = stringArgument(arguments, "description")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard arguments?["name"] != nil || arguments?["title"] != nil || arguments?["description"] != nil else {
            return errorResult("At least one of `name`, `title`, or `description` must be provided.")
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let template = try await HackerRankClient(account: resolved).updateInterviewTemplate(
                id: templateID,
                options: InterviewTemplateWriteOptions(name: name, title: title, description: description)
            )
            return interviewTemplateResult(template, account: resolved.label)
        } catch {
            return errorResult("Couldn't update interview template: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func deleteInterviewTemplateTool(
        _ arguments: [String: Value]?,
        account: String?
    ) async -> CallTool.Result {
        guard let templateID = intArgument(arguments, "template_id") else {
            return missingArgument("template_id")
        }
        guard templateID > 0 else { return errorResult("`template_id` must be greater than zero.") }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            _ = try await HackerRankClient(account: resolved).deleteInterviewTemplate(id: templateID)
            return jsonResult([
                "account": resolved.label,
                "deleted_interview_template_id": templateID,
                "deleted": true
            ])
        } catch {
            return errorResult("Couldn't delete interview template: \(error.localizedDescription)")
        }
    }

    private func interviewTemplateResult(_ template: InterviewTemplate, account: String) -> CallTool.Result {
        guard let id = template.id, id > 0 else {
            return errorResult("HackerRank saved the interview template but returned no usable ID.")
        }

        return jsonResult([
            "account": account,
            "template": [
                "id": id,
                "name": template.name ?? "",
                "title": template.title ?? "",
                "description": template.description ?? ""
            ] as [String: Any]
        ])
    }

    @MainActor
    private func createATSCodePairInviteTool(_ arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        guard let rawTitle = stringArgument(arguments, "title") else { return missingArgument("title") }
        guard let rawRequisitionID = stringArgument(arguments, "requisition_id") else {
            return missingArgument("requisition_id")
        }
        guard let rawCandidateID = stringArgument(arguments, "candidate_id") else {
            return missingArgument("candidate_id")
        }
        guard let title = Self.normalizedOptionalString(rawTitle) else {
            return errorResult("`title` must not be empty.")
        }
        guard let requisitionID = Self.normalizedOptionalString(rawRequisitionID) else {
            return errorResult("`requisition_id` must not be empty.")
        }
        guard let candidateID = Self.normalizedOptionalString(rawCandidateID) else {
            return errorResult("`candidate_id` must not be empty.")
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let result = try await HackerRankClient(account: resolved).createATSCodePairInvite(
                title: title,
                requisitionID: requisitionID,
                candidateID: candidateID,
                options: ATSCodePairOptions(sendEmail: boolArgument(arguments, "send_email"))
            )
            let createdID = Self.validatedCreatedID(result.id)
            let createdURL = result.url.flatMap(URL.remoteWebURL(from:))?.absoluteString
            guard createdID != nil || createdURL != nil else {
                return errorResult("HackerRank created the CodePair invite but returned no usable ID or URL.")
            }

            return jsonResult([
                "account": resolved.label,
                "ats_invite": [
                    "id": createdID ?? "",
                    "url": createdURL ?? "",
                    "status": result.status ?? "",
                    "email": result.email ?? ""
                ]
            ])
        } catch {
            return errorResult("Couldn't create ATS CodePair invite: \(error.localizedDescription)")
        }
    }

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    private func createATSCodeScreenInviteTool(
        _ arguments: [String: Value]?,
        account: String?
    ) async -> CallTool.Result {
        guard let rawTestID = stringArgument(arguments, "test_id") else { return missingArgument("test_id") }
        guard let rawRequisitionID = stringArgument(arguments, "requisition_id") else {
            return missingArgument("requisition_id")
        }
        guard let rawCandidateID = stringArgument(arguments, "candidate_id") else {
            return missingArgument("candidate_id")
        }
        guard let rawEmail = stringArgument(arguments, "email") else { return missingArgument("email") }
        guard let testID = Self.normalizedOptionalString(rawTestID) else {
            return errorResult("`test_id` must not be empty.")
        }
        guard let requisitionID = Self.normalizedOptionalString(rawRequisitionID) else {
            return errorResult("`requisition_id` must not be empty.")
        }
        guard let candidateID = Self.normalizedOptionalString(rawCandidateID) else {
            return errorResult("`candidate_id` must not be empty.")
        }

        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailValidation.isLikelyValid(email) else {
            return errorResult("`email` must be a valid email address.")
        }
        guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

        do {
            let result = try await HackerRankClient(account: resolved).createATSCodeScreenInvite(
                testID: testID,
                requisitionID: requisitionID,
                candidateID: candidateID,
                email: email,
                options: ATSCodeScreenOptions(sendEmail: boolArgument(arguments, "send_email"))
            )
            let createdID = Self.validatedCreatedID(result.id)
            let createdURL = result.url.flatMap(URL.remoteWebURL(from:))?.absoluteString
            guard createdID != nil || createdURL != nil else {
                return errorResult("HackerRank created the CodeScreen invite but returned no usable ID or URL.")
            }

            return jsonResult([
                "account": resolved.label,
                "ats_invite": [
                    "id": createdID ?? "",
                    "url": createdURL ?? "",
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
        func string(
            _ description: String,
            minLength: Int? = nil,
            format: String? = nil,
            allowedValues: [String]? = nil
        ) -> [String: Any] {
            var schema: [String: Any] = ["type": "string", "description": description]
            if let minLength { schema["minLength"] = minLength }
            if let format { schema["format"] = format }
            if let allowedValues { schema["enum"] = allowedValues }
            return schema
        }
        func integer(_ description: String, minimum: Int? = nil, maximum: Int? = nil) -> [String: Any] {
            var schema: [String: Any] = ["type": "integer", "description": description]
            if let minimum { schema["minimum"] = minimum }
            if let maximum { schema["maximum"] = maximum }
            return schema
        }
        func boolean(_ description: String) -> [String: Any] {
            ["type": "boolean", "description": description]
        }
        func url(_ description: String) -> [String: Any] {
            ["type": "string", "format": "uri", "description": description]
        }
        func dateTime(_ description: String) -> [String: Any] {
            ["type": "string", "format": "date-time", "description": description]
        }
        func email(_ description: String) -> [String: Any] {
            ["type": "string", "format": "email", "minLength": 1, "description": description]
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
                "inputSchema": [
                    "type": "object", "properties": properties, "required": required,
                    "additionalProperties": false
                ]
            ]
        }
        func testProperties(nameDescription: String, account: [String: Any]) -> [String: Any] {
            [
                "name": string(nameDescription, minLength: 1),
                "duration": integer("Assessment duration in minutes.", minimum: 1),
                "cutoff_score": integer("Passing score threshold.", minimum: 0),
                "instructions": string("Candidate-facing instructions."),
                "start_time": dateTime("ISO-8601 assessment window start."),
                "end_time": dateTime("ISO-8601 assessment window end."),
                "languages": [
                    "type": "array", "items": ["type": "string", "minLength": 1],
                    "description": "Allowed programming languages."
                ],
                "tags": [
                    "type": "array", "items": ["type": "string", "minLength": 1],
                    "description": "Assessment tags."
                ],
                "shuffle_questions": boolean("Shuffle question order."),
                "enable_proctoring": boolean("Enable proctoring."),
                "account": account
            ]
        }
        return [
            write("create_test", "Create a HackerRank test with optional assessment settings.",
                  properties: testProperties(nameDescription: "The test's name.", account: account),
                  required: ["name"]),
            write("update_test", "Update a HackerRank test and its assessment settings.",
                  properties: testProperties(nameDescription: "The test's name.", account: account)
                      .merging(["test_id": string("The test's id.", minLength: 1)]) { current, _ in current },
                  required: ["test_id", "name"]),
            write("archive_test", "Archive a test.",
                  properties: ["test_id": string("The test's id."), "account": account],
                  required: ["test_id"]),
            write("delete_test", "Permanently delete a test.",
                  properties: ["test_id": string("The test's id.", minLength: 1), "account": account],
                  required: ["test_id"], destructive: true),
            write("invite_candidate", "Invite a candidate to a test by email.",
                  properties: [
                      "test_id": string("The test's id."), "email": email("The candidate's email."),
                      "full_name": string("The candidate's name (optional)."),
                      "send_email": boolean("Email the invite (default true)."),
                      "additional_time": integer("Extra time accommodation in minutes (0–1,440)."),
                      "valid_from": dateTime("ISO-8601 timestamp before which the invite is inactive."),
                      "valid_until": dateTime("ISO-8601 timestamp after which the invite expires."),
                      "email_subject": string("Custom invitation email subject."),
                      "email_message": string("Custom invitation email message."),
                      "template_id": string("Invitation email template id."),
                      "evaluator_email": string("Evaluator email assigned to the invite."),
                      "finish_url": url("HTTP(S) URL to send the candidate to after finishing."),
                      "result_url": url("HTTP(S) result/report callback or redirect URL."),
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
                      "ats_state": integer("HackerRank ATS state code (0–22).", minimum: 0, maximum: 22),
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
                      "email": string("The user's email.", minLength: 1, format: "email"),
                      "first_name": string("The user's first name.", minLength: 1),
                      "last_name": string("Last name (optional)."),
                      "role": string(
                          "Role: recruiter, developer, or interviewer.",
                          allowedValues: ["recruiter", "developer", "interviewer"]
                      ),
                      "team_id": string(
                          "Id of the team the user will belong to (see list_teams).",
                          minLength: 1
                      ),
                      "account": account
                  ],
                  required: ["email", "first_name", "role", "team_id"]),
            write("update_user", "Update an organisation user.",
                  properties: [
                      "user_id": string("The user's id."),
                      "first_name": string("The user's first name."),
                      "last_name": string("The user's last name."),
                      "country": string("Country."),
                      "role": string(
                          "Role: recruiter, developer, or interviewer.",
                          allowedValues: ["recruiter", "developer", "interviewer"]
                      ),
                      "phone": string("Phone number."),
                      "questions_permission": integer("Questions permission level.", minimum: 0, maximum: 3),
                      "tests_permission": integer("Tests permission level.", minimum: 0, maximum: 3),
                      "interviews_permission": integer("Interviews permission level.", minimum: 0, maximum: 3),
                      "candidates_permission": integer("Candidates permission level.", minimum: 0, maximum: 3),
                      "shared_questions_permission": integer("Shared questions permission.", minimum: 0, maximum: 3),
                      "shared_tests_permission": integer("Shared tests permission.", minimum: 0, maximum: 3),
                      "shared_interviews_permission": integer("Shared interviews permission.", minimum: 0, maximum: 3),
                      "shared_candidates_permission": integer("Shared candidates permission.", minimum: 0, maximum: 3),
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
                      "name": string("The question's name.", minLength: 1),
                      "type": string("Question type.", allowedValues: Self.supportedQuestionTypes),
                      "status": string(
                          "Question lifecycle status.",
                          allowedValues: QuestionLifecycleStatus.allCases.map(\.rawValue)
                      ),
                      "languages": ["type": "array", "items": ["type": "string"],
                                    "description": "Allowed languages; a comma-separated string is also accepted."],
                      "problem_statement": string("Problem statement, typically Markdown or HTML."),
                      "recommended_duration": integer("Recommended duration in minutes.", minimum: 0),
                      "tags": ["type": "array", "items": ["type": "string"],
                               "description": "Question tags; a comma-separated string is also accepted."],
                      "max_score": [
                          "type": "number", "minimum": 0,
                          "description": "Maximum achievable score."
                      ],
                      "skills": ["type": "array", "items": ["type": "string"],
                                 "description": "Skills assessed; a comma-separated string is also accepted."],
                      "account": account
                  ],
                  required: ["name", "type"]),
            write("update_question", "Update question metadata.",
                  properties: [
                      "question_id": string("The question's id."),
                      "name": string("The question's name."),
                      "type": string("Question type.", allowedValues: Self.supportedQuestionTypes),
                      "status": string(
                          "Question lifecycle status.",
                          allowedValues: QuestionLifecycleStatus.allCases.map(\.rawValue)
                      ),
                      "languages": ["type": "array", "items": ["type": "string"],
                                    "description": "Allowed languages; a comma-separated string is also accepted."],
                      "problem_statement": string("Problem statement, typically Markdown or HTML."),
                      "recommended_duration": integer("Recommended duration in minutes.", minimum: 0),
                      "tags": ["type": "array", "items": ["type": "string"],
                               "description": "Question tags; a comma-separated string is also accepted."],
                      "max_score": [
                          "type": "number", "minimum": 0,
                          "description": "Maximum achievable score."
                      ],
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
                  properties: ["name": string("The team's name.", minLength: 1), "account": account],
                  required: ["name"]),
            write("update_team", "Update a team.",
                  properties: [
                      "team_id": string("The team's id."),
                      "name": string("The team's name."),
                      "recruiter_cap": integer("Recruiter seat cap.", minimum: 0),
                      "developer_cap": integer("Developer seat cap.", minimum: 0),
                      "invite_as": string(
                          "Default invite role.",
                          allowedValues: ["recruiter", "interviewer", "developer"]
                      ),
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
                      "team_id": string("The team's id."),
                      "email": string("The member's email.", minLength: 1, format: "email"),
                      "role": string(
                          "The member's role (optional).",
                          allowedValues: ["recruiter", "interviewer", "developer"]
                      ),
                      "account": account
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
                  properties: [
                      "team_id": string("The team's id.", minLength: 1),
                      "user_id": string("The member's user id.", minLength: 1),
                      "account": account
                  ],
                  required: ["team_id", "user_id"], destructive: true),
            write("create_pad", "Create an instant collaborative Pad interview.",
                  properties: ["title": string("The pad's title (optional)."), "account": account], required: []),
            write("schedule_interview", "Schedule an interview at an ISO-8601 start time.",
                  properties: [
                      "title": string("The interview's title."),
                      "from": string("Start time, ISO-8601 (e.g. 2026-07-01T14:00:00Z)."),
                      "candidate_email": string("The candidate's email (optional).", format: "email"),
                      "notes": string("Notes (optional)."), "account": account
                  ],
                  required: ["title", "from"]),
            write("delete_interview", "Delete an interview.",
                  properties: ["interview_id": string("The interview's id."), "account": account],
                  required: ["interview_id"], destructive: true),
            write("create_interview_template", "Create a native HackerRank interview template.",
                  properties: [
                      "name": string("The template's name.", minLength: 1),
                      "title": string("Default interview title."),
                      "description": string("Default interview description."),
                      "account": account
                  ],
                  required: ["name"]),
            write("update_interview_template", "Update a native HackerRank interview template.",
                  properties: [
                      "template_id": integer("The template id.", minimum: 1),
                      "name": string("The template's name."),
                      "title": string("Default interview title."),
                      "description": string("Default interview description."),
                      "account": account
                  ],
                  required: ["template_id"]),
            write("delete_interview_template", "Delete a native HackerRank interview template.",
                  properties: [
                      "template_id": integer("The template id.", minimum: 1),
                      "account": account
                  ],
                  required: ["template_id"], destructive: true),
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
                      "email": string("The candidate's email.", format: "email"),
                      "send_email": boolean("Email the invite."),
                      "account": account
                  ],
                  required: ["test_id", "requisition_id", "candidate_id", "email"])
        ]
    }
}
